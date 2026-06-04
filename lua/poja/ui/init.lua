local parser = require("poja.ui.parser")

local presets = parser.annotation_presets
local M = {}

local function insert_field(name, typ, annotations)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local field_end
  local in_class = false
  local brace_depth = 0

  for i, line in ipairs(lines) do
    if not in_class then
      if line:match("{") then
        in_class = true
        brace_depth = 1
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
    return
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
end

local function prompt_annotations(name, typ, pi, annots)
  if pi > #presets then
    insert_field(name, typ, annots)
    vim.ui.input({ prompt = "Add another? (y/n): " }, function(input)
      if input and input:lower():sub(1, 1) == "y" then
        start_prompts()
      end
    end)
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
          prompt_annotations(name, typ, pi + 1, annots)
        end)
      else
        table.insert(annots, preset.annotation)
        prompt_annotations(name, typ, pi + 1, annots)
      end
    else
      prompt_annotations(name, typ, pi + 1, annots)
    end
  end)
end

local function start_prompts()
  vim.ui.input({ prompt = "Field name: " }, function(name)
    if not name or name == "" then return end
    vim.ui.input({ prompt = "Field type: " }, function(typ)
      if not typ or typ == "" then return end
      prompt_annotations(name, typ, 1, {})
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
