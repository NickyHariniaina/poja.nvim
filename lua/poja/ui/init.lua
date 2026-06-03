local parser = require("poja.ui.parser")

local M = {}

function M.edit_fields()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" or not bufname:match("%.java$") then
    vim.notify("poja: not a Java file", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local class_name = ""
  for _, line in ipairs(lines) do
    local cn = line:match("public%s+class%s+(%w+)")
    if cn then
      class_name = cn
      break
    end
  end
  if class_name == "" then
    vim.notify("poja: no class found in buffer", vim.log.levels.WARN)
    return
  end

  local fields = parser.parse_fields_from_buffer(lines)
  if #fields == 0 then
    vim.notify("poja: no fields found", vim.log.levels.WARN)
    return
  end

  local form_width = 80
  local form_height = #fields + 5
  local max_height = vim.o.lines - 4
  if form_height > max_height then
    form_height = max_height
  end

  local form_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(form_buf, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(form_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(form_buf, "poja://fields/" .. class_name)

  local form_lines = {}
  table.insert(form_lines, "# Fields for " .. class_name .. " — edit freely, then :w")
  table.insert(form_lines, "# Format: name:Type:@Annotation1 @Annotation2(...)")
  table.insert(form_lines, "")
  for _, f in ipairs(fields) do
    table.insert(form_lines, parser.format_field_to_form(f))
  end
  vim.api.nvim_buf_set_lines(form_buf, 0, -1, false, form_lines)
  vim.api.nvim_buf_set_option(form_buf, "modified", false)

  local win_opts = {
    style = "minimal",
    relative = "editor",
    width = form_width,
    height = form_height,
    row = math.floor((vim.o.lines - form_height) / 3),
    col = math.floor((vim.o.columns - form_width) / 2),
    zindex = 150,
    border = "single",
    title = " Poja Fields — " .. class_name .. " ",
    title_pos = "center",
  }

  local form_win = vim.api.nvim_open_win(form_buf, true, win_opts)
  vim.api.nvim_win_set_option(form_win, "cursorline", true)
  vim.api.nvim_buf_set_keymap(form_buf, "n", "q", ":close<CR>", { silent = true, noremap = true })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = form_buf,
    once = true,
    callback = function()
      local form_lines = vim.api.nvim_buf_get_lines(form_buf, 0, -1, false)
      local new_fields = {}
      for _, line in ipairs(form_lines) do
        if not line:match("^#") and line:match("%S") then
          local field = parser.form_to_field_block(line)
          if field then
            table.insert(new_fields, field)
          end
        end
      end

      if #new_fields == 0 then
        vim.notify("poja: no valid fields in form", vim.log.levels.WARN)
        vim.api.nvim_buf_set_option(form_buf, "modified", false)
        return
      end

      local orig_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local field_start, field_end
      local in_class = false
      local brace_depth = 0

      for i, line in ipairs(orig_lines) do
        if not in_class then
          if line:match("{") then
            in_class = true
            brace_depth = 1
            field_start = i + 1
          end
        else
          brace_depth = brace_depth + line:gsub("[^%{]", ""):len() - line:gsub("[^%}]", ""):len()

          if parser.is_method_or_constructor(line) and not line:match(";%s*$") then
            field_end = i - 1
            break
          end

          if brace_depth < 1 and line:match("}") then
            field_end = i - 1
            break
          end
        end
      end

      if not field_start or not field_end then
        vim.notify("poja: could not determine field region", vim.log.levels.ERROR)
        return
      end

      local indent = "  "
      for i = field_start, field_end do
        local idt = orig_lines[i]:match("^(%s+)")
        if idt then
          indent = idt
          break
        end
      end

      local new_lines = {}
      for idx, f in ipairs(new_fields) do
        if idx > 1 then
          table.insert(new_lines, "")
        end
        local block = parser.field_block_to_code(f, indent)
        for _, bl in ipairs(block) do
          table.insert(new_lines, bl)
        end
      end

      vim.api.nvim_buf_set_lines(bufnr, field_start - 1, field_end, false, new_lines)
      vim.api.nvim_buf_set_option(form_buf, "modified", false)
      vim.api.nvim_win_close(form_win, true)
      vim.notify("poja: fields updated in " .. class_name .. ".java", vim.log.levels.INFO)
    end,
  })
end

return M
