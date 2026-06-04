local parser = require("poja.ui.parser")

local presets = parser.annotation_presets
local M = {}

local function ensure_imports(bufnr, lines, import_keys)
  if not import_keys or #import_keys == 0 then return end

  local needed = {}
  for _, key in ipairs(import_keys) do
    for _, preset in ipairs(presets) do
      if preset.key == key and preset.import then
        needed["import " .. preset.import .. ";"] = true
        break
      end
    end
  end

  if not next(needed) then return end

  local existing = {}
  local last_import = -1

  for i, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    if trimmed:match("^import%s+") then
      existing[trimmed] = true
      last_import = i
    end
  end

  local wildcards = {}
  for imp, _ in pairs(existing) do
    local pkg = imp:match("^import%s+(.*)%.%*;%s*$")
    if pkg then wildcards[pkg] = true end
  end

  local to_insert = {}
  for imp, _ in pairs(needed) do
    if not existing[imp] then
      local pkg = imp:match("^import%s+(.*)%.[^%.]+;%s*$")
      local covered = false
      for wc, _ in pairs(wildcards) do
        if pkg and (pkg == wc or pkg:find(wc .. "%.", 1, true)) then
          covered = true
          break
        end
      end
      if not covered then
        table.insert(to_insert, imp)
      end
    end
  end

  if #to_insert == 0 then return end
  table.sort(to_insert)
  if last_import >= 0 then
    vim.api.nvim_buf_set_lines(bufnr, last_import, last_import, false, to_insert)
  end
end

local function insert_field(name, typ, annotations, import_keys)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  ensure_imports(bufnr, lines, import_keys)
  lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local field_end
  local class_found = false
  local brace_depth = 0

  for i, line in ipairs(lines) do
    if not class_found then
      if line:match("class%s+%w+") then
        class_found = true
        brace_depth = line:gsub("[^%{]", ""):len()
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

  if not field_end then
    vim.notify("poja: could not find field region", vim.log.levels.ERROR)
    return false
  end

  local indent = "  "
  for i = 1, field_end do
    local idt = lines[i]:match("^(%s+)")
    if idt then indent = idt; break end
  end

  local field = { name = name, type = typ, annotations = annotations }
  local block = parser.field_block_to_code(field, indent)

  local sep = field_end > 0 and lines[field_end]:match("%S") and { "" } or {}
  vim.api.nvim_buf_set_lines(bufnr, field_end, field_end, false, sep)
  local new_end = field_end + #sep
  vim.api.nvim_buf_set_lines(bufnr, new_end, new_end, false, block)
  return true
end

local function prompt_annotations(name, typ, pi, annots, import_keys)
  if pi > #presets then
    local ok = insert_field(name, typ, annots, import_keys)
    if ok then
      vim.ui.input({ prompt = "Add another? (y/n): " }, function(input)
        if input and input:lower():sub(1, 1) == "y" then
          start_prompts()
        end
      end)
    end
    return
  end

  local preset = presets[pi]
  vim.ui.input({ prompt = "@" .. preset.label .. "? (y/n): " }, function(input)
    if input and input:lower():sub(1, 1) == "y" then
      if preset.has_params then
        local parts = {}
        for k, v in pairs(preset.param_defs) do
          table.insert(parts, k .. "=" .. v)
        end
        vim.ui.input({ prompt = preset.label .. " (" .. table.concat(parts, ",") .. "): " }, function(params_input)
          local params = {}
          if params_input and params_input ~= "" then
            for pair in params_input:gmatch("[^,]+") do
              local k, v = pair:match("^%s*(%w+)%s*=%s*(.-)%s*$")
              if k and v then params[k] = v end
            end
          end
          table.insert(annots, parser.preset_to_annotation(preset, params))
          table.insert(import_keys, preset.key)
          prompt_annotations(name, typ, pi + 1, annots, import_keys)
        end)
      else
        table.insert(annots, preset.annotation)
        table.insert(import_keys, preset.key)
        prompt_annotations(name, typ, pi + 1, annots, import_keys)
      end
    else
      prompt_annotations(name, typ, pi + 1, annots, import_keys)
    end
  end)
end

local function start_prompts()
  vim.ui.input({ prompt = "Field name: " }, function(name)
    if not name or name == "" then return end
    vim.ui.input({ prompt = "Field type: " }, function(typ)
      if not typ or typ == "" then return end
      prompt_annotations(name, typ, 1, {}, {})
    end)
  end)
end

function M.edit_fields()
  local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if bufname == "" or not bufname:match("%.java$") then
    vim.notify("poja: not a Java file", vim.log.levels.WARN)
    return
  end
  start_prompts()
end

return M
