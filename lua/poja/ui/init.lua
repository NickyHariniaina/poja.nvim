local parser = require("poja.ui.parser")

local presets = parser.annotation_presets
local PRESETS_PER_ROW = 4
local CHK_WIDTH = 18

local M = {}

local function fmt_checkbox(checked, label)
  local mark = checked and "x" or " "
  return "[ " .. mark .. " ] " .. label
end

local function pad_to(s, w)
  if #s >= w then return s:sub(1, w) end
  return s .. string.rep(" ", w - #s)
end

local function preset_display(preset, checked, params)
  local label = preset.label
  if checked and preset.has_params and params and next(params) then
    local parts = {}
    for k, v in pairs(params) do
      if v and v ~= "" then
        table.insert(parts, k .. "=" .. v)
      end
    end
    if #parts > 0 then
      label = label .. "(" .. table.concat(parts, ",") .. ")"
    end
  end
  return pad_to(fmt_checkbox(checked, label), CHK_WIDTH)
end

local function build_state(fields)
  local checks = {}
  local params = {}
  local extras = {}

  for fi, field in ipairs(fields) do
    checks[fi] = {}
    params[fi] = {}
    extras[fi] = {}

    local matched = {}
    for _, annot in ipairs(field.annotations) do
      local key, vals = parser.match_annotation_to_preset(annot)
      if key then
        checks[fi][key] = true
        if vals and next(vals) then
          params[fi][key] = vals
        end
        matched[annot] = true
      end
    end

    for _, annot in ipairs(field.annotations) do
      if not matched[annot] then
        table.insert(extras[fi], annot)
      end
    end
  end

  return {
    fields = fields,
    checks = checks,
    params = params,
    extras = extras,
    current_field = 1,
    current_preset = 1,
  }
end

local function block_lines()
  return 1 + math.ceil(#presets / PRESETS_PER_ROW) + 1
end

local function total_lines(num_fields)
  return 2 + num_fields * block_lines()
end

local function field_header_line(fi)
  return 3 + (fi - 1) * block_lines()
end

local function field_preset_line(fi, pi)
  local hdr = field_header_line(fi)
  local row = math.floor((pi - 1) / PRESETS_PER_ROW)
  return hdr + 1 + row
end

local function field_preset_col(pi)
  return ((pi - 1) % PRESETS_PER_ROW) * CHK_WIDTH
end

local function render_form(state)
  local lines = {}
  table.insert(lines, "# Poja Fields    a:add  Space: toggle  v: params  :w save  q: close")
  table.insert(lines, "#")
  for fi, field in ipairs(state.fields) do
    table.insert(lines, "# " .. field.name .. " : " .. field.type)
    local row_line = ""
    for pi, preset in ipairs(presets) do
      local checked = state.checks[fi][preset.key]
      local vals = state.params[fi][preset.key]
      row_line = row_line .. preset_display(preset, checked, vals)
      if pi % PRESETS_PER_ROW == 0 and pi < #presets then
        table.insert(lines, row_line)
        row_line = ""
      end
    end
    if row_line ~= "" then
      table.insert(lines, row_line)
    end
    table.insert(lines, "#")
  end
  return lines
end

local function refresh_buf(bufnr)
  local state = vim.b[bufnr].poja_state
  vim.bo[bufnr].modifiable = true
  local lines = render_form(state)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  M.move_cursor(bufnr)
end

function M.move_cursor(bufnr)
  local state = vim.b[bufnr].poja_state
  local win = state._win
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local line = field_preset_line(state.current_field, state.current_preset)
  local col = field_preset_col(state.current_preset)
  pcall(vim.api.nvim_win_set_cursor, win, { line, col })
end

function M._j(buf)
  local s = vim.b[buf].poja_state
  if s.current_field < #s.fields then
    s.current_field = s.current_field + 1
    M.move_cursor(buf)
  end
end

function M._k(buf)
  local s = vim.b[buf].poja_state
  if s.current_field > 1 then
    s.current_field = s.current_field - 1
    M.move_cursor(buf)
  end
end

function M._h(buf)
  local s = vim.b[buf].poja_state
  if s.current_preset > 1 then
    s.current_preset = s.current_preset - 1
    M.move_cursor(buf)
  end
end

function M._l(buf)
  local s = vim.b[buf].poja_state
  if s.current_preset < #presets then
    s.current_preset = s.current_preset + 1
    M.move_cursor(buf)
  end
end

function M._toggle(buf)
  local s = vim.b[buf].poja_state
  local key = presets[s.current_preset].key
  s.checks[s.current_field][key] = not s.checks[s.current_field][key]
  if not s.checks[s.current_field][key] then
    s.params[s.current_field][key] = nil
  end
  refresh_buf(buf)
end

function M._params(buf)
  local s = vim.b[buf].poja_state
  local preset = presets[s.current_preset]
  if not preset.has_params then
    vim.notify("poja: " .. preset.label .. " has no parameters", vim.log.levels.INFO)
    return
  end
  local fi = s.current_field
  s.checks[fi][preset.key] = true
  if not s.params[fi][preset.key] then
    s.params[fi][preset.key] = vim.deepcopy(preset.param_defs)
  end
  local current = s.params[fi][preset.key]
  vim.ui.input({ prompt = preset.label .. " (enter params, e.g. min=0,max=255): " }, function(input)
    if not input or input == "" then
      s.checks[fi][preset.key] = false
      s.params[fi][preset.key] = nil
    else
      for k, _ in pairs(preset.param_defs) do
        local val = input:match(k .. "%s*=%s*([^, ]+)")
        if val then
          current[k] = val
        end
      end
    end
    refresh_buf(buf)
  end)
end

function M._add_field(buf)
  local s = vim.b[buf].poja_state
  vim.ui.input({ prompt = "Field name: " }, function(name)
    if not name or name == "" then return end
    vim.ui.input({ prompt = "Field type (e.g. String, Integer): " }, function(typ)
      if not typ or typ == "" then return end
      local fi = #s.fields + 1
      table.insert(s.fields, { name = name, type = typ, annotations = {} })
      s.checks[fi] = {}
      s.params[fi] = {}
      s.extras[fi] = {}
      s.current_field = fi
      s.current_preset = 1
      refresh_buf(buf)
    end)
  end)
end

local function save_fields(bufnr)
  local s = vim.b[bufnr].poja_state
  local target_bufnr = s._target
  local form_win = s._win

  local new_fields = {}
  for fi, field in ipairs(s.fields) do
    local annotations = {}
    for _, annot in ipairs(s.extras[fi]) do
      table.insert(annotations, annot)
    end
    for pi, preset in ipairs(presets) do
      if s.checks[fi][preset.key] then
        local vals = s.params[fi][preset.key]
        table.insert(annotations, parser.preset_to_annotation(preset, vals))
      end
    end
    table.insert(new_fields, {
      name = field.name,
      type = field.type,
      annotations = annotations,
    })
  end

  if #new_fields == 0 then
    vim.notify("poja: no valid fields", vim.log.levels.WARN)
    return
  end

  local orig_lines = vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
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
    if idt then indent = idt; break end
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

  vim.api.nvim_buf_set_lines(target_bufnr, field_start - 1, field_end, false, new_lines)
  if form_win and vim.api.nvim_win_is_valid(form_win) then
    vim.api.nvim_win_close(form_win, true)
  end
  vim.notify("poja: fields updated", vim.log.levels.INFO)
end

local function setup_keymaps(form_buf, form_win)
  local opts = { silent = true, nowait = true }

  vim.api.nvim_buf_set_keymap(form_buf, "n", "j",
    "<cmd>lua require('poja.ui')._j(" .. form_buf .. ")<CR>", opts)
  vim.api.nvim_buf_set_keymap(form_buf, "n", "k",
    "<cmd>lua require('poja.ui')._k(" .. form_buf .. ")<CR>", opts)
  vim.api.nvim_buf_set_keymap(form_buf, "n", "h",
    "<cmd>lua require('poja.ui')._h(" .. form_buf .. ")<CR>", opts)
  vim.api.nvim_buf_set_keymap(form_buf, "n", "l",
    "<cmd>lua require('poja.ui')._l(" .. form_buf .. ")<CR>", opts)
  vim.api.nvim_buf_set_keymap(form_buf, "n", "<Space>",
    "<cmd>lua require('poja.ui')._toggle(" .. form_buf .. ")<CR>", opts)
  vim.api.nvim_buf_set_keymap(form_buf, "n", "<CR>",
    "<cmd>lua require('poja.ui')._toggle(" .. form_buf .. ")<CR>", opts)
  vim.api.nvim_buf_set_keymap(form_buf, "n", "v",
    "<cmd>lua require('poja.ui')._params(" .. form_buf .. ")<CR>", opts)
  vim.api.nvim_buf_set_keymap(form_buf, "n", "a",
    "<cmd>lua require('poja.ui')._add_field(" .. form_buf .. ")<CR>", opts)
  vim.api.nvim_buf_set_keymap(form_buf, "n", "q",
    "<cmd>close<CR>", opts)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = form_buf,
    once = true,
    callback = function()
      save_fields(form_buf)
    end,
  })
end

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

  local state = build_state(fields)

  local total_h = total_lines(#state.fields)
  local form_height = total_h + 2
  local max_height = vim.o.lines - 4
  if form_height > max_height then form_height = max_height end
  local form_width = CHK_WIDTH * PRESETS_PER_ROW + 4

  local form_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(form_buf, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(form_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_name(form_buf, "poja://fields/" .. class_name)

  local form_lines = render_form(state)
  vim.api.nvim_buf_set_lines(form_buf, 0, -1, false, form_lines)
  vim.api.nvim_buf_set_option(form_buf, "modified", false)
  vim.bo[form_buf].modifiable = false

  local win_opts = {
    style = "minimal",
    relative = "editor",
    width = form_width,
    height = form_height,
    row = math.floor((vim.o.lines - form_height) / 3),
    col = math.floor((vim.o.columns - form_width) / 2),
    zindex = 150,
    border = "single",
    title = " Poja Fields \226\128\148 " .. class_name .. " ",
    title_pos = "center",
  }

  local form_win = vim.api.nvim_open_win(form_buf, true, win_opts)
  vim.api.nvim_win_set_option(form_win, "cursorline", true)

  state._win = form_win
  state._target = bufnr
  vim.b[form_buf].poja_state = state

  M.move_cursor(form_buf)
  setup_keymaps(form_buf, form_win)
end

return M
