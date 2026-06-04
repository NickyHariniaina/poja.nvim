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

local function field_start_line(fi)
  return 2 + (fi - 1) * block_lines()
end

local function field_preset_line(fi, pi)
  local start = field_start_line(fi) + 1
  local row = math.floor((pi - 1) / PRESETS_PER_ROW)
  return start + row
end

local function field_preset_col(pi)
  return ((pi - 1) % PRESETS_PER_ROW) * CHK_WIDTH
end

local function render_form(state)
  local lines = {}
  table.insert(lines, "# Poja Fields          Tab: toggle  v: params  :w save  q: close")
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

local function move_cursor(form_win, state)
  local line = field_preset_line(state.current_field, state.current_preset)
  local col = field_preset_col(state.current_preset)
  vim.api.nvim_win_set_cursor(form_win, { line, col })
end

local function refresh_buf(form_buf, form_win, state)
  vim.bo[form_buf].modifiable = true
  local lines = render_form(state)
  vim.api.nvim_buf_set_lines(form_buf, 0, -1, false, lines)
  vim.bo[form_buf].modifiable = false
  move_cursor(form_win, state)
end

local function toggle_current(form_buf, form_win, state)
  local fi = state.current_field
  local preset = presets[state.current_preset]
  local key = preset.key
  state.checks[fi][key] = not state.checks[fi][key]
  if not state.checks[fi][key] then
    state.params[fi][key] = nil
  end
  refresh_buf(form_buf, form_win, state)
end

local function edit_params_current(form_buf, form_win, state)
  local fi = state.current_field
  local preset = presets[state.current_preset]
  if not preset.has_params then
    vim.notify("poja: " .. preset.label .. " has no parameters", vim.log.levels.INFO)
    return
  end
  state.checks[fi][preset.key] = true
  if not state.params[fi][preset.key] then
    state.params[fi][preset.key] = vim.deepcopy(preset.param_defs)
  end
  local current = state.params[fi][preset.key]
  local input_parts = {}
  for k, default in pairs(preset.param_defs) do
    local val = current[k] or default
    table.insert(input_parts, k .. "=" .. val)
  end
  vim.ui.input({ prompt = preset.label .. " (" .. table.concat(input_parts, ", ") .. "): " }, function(input)
    if not input or input == "" then
      state.checks[fi][preset.key] = false
      state.params[fi][preset.key] = nil
    else
      for k, _ in pairs(preset.param_defs) do
        local val = input:match(k .. "%s*=%s*([^, ]+)")
        if val then
          current[k] = val
        end
      end
    end
    refresh_buf(form_buf, form_win, state)
  end)
end

local function save_fields(form_buf, form_win, state, target_bufnr)
  local new_fields = {}
  for fi, field in ipairs(state.fields) do
    local annotations = {}
    for _, annot in ipairs(state.extras[fi]) do
      table.insert(annotations, annot)
    end
    for pi, preset in ipairs(presets) do
      if state.checks[fi][preset.key] then
        local vals = state.params[fi][preset.key]
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
  vim.api.nvim_buf_set_option(form_buf, "modified", false)
  vim.api.nvim_win_close(form_win, true)
  vim.notify("poja: fields updated", vim.log.levels.INFO)
end

local function setup_keymaps(form_buf, form_win, state)
  local opts = { buffer = form_buf, nowait = true, silent = true, noremap = true }

  vim.keymap.set("n", "j", function()
    if state.current_field < #state.fields then
      state.current_field = state.current_field + 1
      state.current_preset = math.min(state.current_preset, #presets)
      move_cursor(form_win, state)
    end
  end, opts)

  vim.keymap.set("n", "k", function()
    if state.current_field > 1 then
      state.current_field = state.current_field - 1
      state.current_preset = math.min(state.current_preset, #presets)
      move_cursor(form_win, state)
    end
  end, opts)

  vim.keymap.set("n", "l", function()
    if state.current_preset < #presets then
      state.current_preset = state.current_preset + 1
      move_cursor(form_win, state)
    end
  end, opts)

  vim.keymap.set("n", "h", function()
    if state.current_preset > 1 then
      state.current_preset = state.current_preset - 1
      move_cursor(form_win, state)
    end
  end, opts)

  vim.keymap.set("n", "<Space>", function()
    toggle_current(form_buf, form_win, state)
  end, opts)

  vim.keymap.set("n", "<CR>", function()
    toggle_current(form_buf, form_win, state)
  end, opts)

  vim.keymap.set("n", "v", function()
    edit_params_current(form_buf, form_win, state)
  end, opts)

  vim.keymap.set("n", "q", ":close<CR>", opts)
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

  move_cursor(form_win, state)
  setup_keymaps(form_buf, form_win, state)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = form_buf,
    once = true,
    callback = function()
      save_fields(form_buf, form_win, state, bufnr)
    end,
  })
end

return M
