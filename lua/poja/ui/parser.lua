local M = {}

function M.is_annotation_line(line)
  return line:match("^%s*@")
end

function M.is_field_declaration(line)
  return line:match("^%s*private%s+.*;%s*$")
    or line:match("^%s*protected%s+.*;%s*$")
    or line:match("^%s*public%s+.*;%s*$")
end

function M.is_method_or_constructor(line)
  local trimmed = line:match("^%s*(.*)")
  if not trimmed then return false end
  if trimmed:match("^public%s+.*%(") then return true end
  if trimmed:match("^private%s+.*%(") then return true end
  if trimmed:match("^protected%s+.*%(") then return true end
  if trimmed:match("^static%s+.*%(") then return true end
  return false
end

function M.extract_field_name(line)
  local name = line:match("^%s*private%s+[%w%.<>%[%],%?%s]+%s+(%w+)%s*[=;]")
  if not name then
    name = line:match("^%s*protected%s+[%w%.<>%[%],%?%s]+%s+(%w+)%s*[=;]")
  end
  if not name then
    name = line:match("^%s*public%s+[%w%.<>%[%],%?%s]+%s+(%w+)%s*[=;]")
  end
  return name
end

function M.extract_field_type(line)
  local typ = line:match("^%s*private%s+([%w%.<>%[%],%?%s]+)%s+%w+%s*[=;]")
  if not typ then
    typ = line:match("^%s*protected%s+([%w%.<>%[%],%?%s]+)%s+%w+%s*[=;]")
  end
  if not typ then
    typ = line:match("^%s*public%s+([%w%.<>%[%],%?%s]+)%s+%w+%s*[=;]")
  end
  if typ then
    typ = typ:gsub("^%s*(.-)%s*$", "%1")
  end
  return typ
end

function M.parse_fields_from_buffer(lines)
  local fields = {}
  local in_class = false
  local brace_depth = 0
  local current_annotations = {}

  for _, line in ipairs(lines) do
    if not in_class then
      if line:match("{") then
        in_class = true
        brace_depth = 1
      end
    else
      brace_depth = brace_depth + line:gsub("[^%{]", ""):len() - line:gsub("[^%}]", ""):len()

      if M.is_method_or_constructor(line) and not line:match(";%s*$") then
        break
      end

      if brace_depth < 1 then
        break
      end

      local trimmed = line:match("^%s*(.*)") or ""

      if trimmed == "" or trimmed:match("^//") or trimmed:match("^%*") then
      elseif M.is_annotation_line(trimmed) then
        table.insert(current_annotations, trimmed:match("^%s*(.-)%s*$"))
      elseif M.is_field_declaration(trimmed) then
        local name = M.extract_field_name(trimmed)
        local typ = M.extract_field_type(trimmed)
        if name and typ then
          table.insert(fields, {
            name = name,
            type = typ,
            annotations = current_annotations,
          })
        end
        current_annotations = {}
      else
        current_annotations = {}
      end
    end
  end

  return fields
end

function M.format_field_to_form(field)
  local annot_str = table.concat(field.annotations, " ")
  return field.name .. ":" .. field.type .. ":" .. annot_str
end

function M.form_to_field_block(line)
  local name, typ, annot_str = line:match("^%s*([^:]+):([^:]+):(.*)$")
  if not name then
    name = line:match("^%s*([^:]+):([^:]+)%s*$")
    if name then
      typ = line:match("^%s*[^:]+:([^:]+)%s*$")
      name = line:match("^%s*([^:]+):")
      annot_str = ""
    end
  end
  if not name then return nil end

  name = name:match("^%s*(.-)%s*$")
  typ = typ:match("^%s*(.-)%s*$")

  local annotations = {}
  if annot_str and annot_str ~= "" then
    for a in annot_str:gmatch("%S+") do
      table.insert(annotations, a)
    end
  end

  return {
    name = name,
    type = typ,
    annotations = annotations,
  }
end

function M.field_block_to_code(field, indent)
  local lines = {}
  for _, a in ipairs(field.annotations) do
    table.insert(lines, indent .. a)
  end
  table.insert(lines, indent .. "private " .. field.type .. " " .. field.name .. ";")
  return lines
end

M.annotation_presets = {
  { key = "notnull",  label = "NotNull",  annotation = "@NotNull",
    import = "jakarta.validation.constraints.NotNull",  has_params = false },
  { key = "notblank", label = "NotBlank", annotation = "@NotBlank",
    import = "jakarta.validation.constraints.NotBlank", has_params = false },
  { key = "notempty", label = "NotEmpty", annotation = "@NotEmpty",
    import = "jakarta.validation.constraints.NotEmpty", has_params = false },
  { key = "size",     label = "Size",     annotation = "@Size",
    import = "jakarta.validation.constraints.Size", has_params = true,
    param_defs = { min = "0", max = "255" } },
  { key = "min",      label = "Min",      annotation = "@Min",
    import = "jakarta.validation.constraints.Min", has_params = true,
    param_defs = { value = "0" } },
  { key = "max",      label = "Max",      annotation = "@Max",
    import = "jakarta.validation.constraints.Max", has_params = true,
    param_defs = { value = "0" } },
  { key = "email",    label = "Email",    annotation = "@Email",
    import = "jakarta.validation.constraints.Email", has_params = false },
  { key = "pattern",  label = "Pattern",  annotation = "@Pattern",
    import = "jakarta.validation.constraints.Pattern", has_params = true,
    param_defs = { regexp = "" } },
}

function M.match_annotation_to_preset(annot_str)
  for _, preset in ipairs(M.annotation_presets) do
    local rest = annot_str:match("^%s*@" .. preset.label .. "%s*(.*)$")
    if rest then
      local params = {}
      if preset.has_params and rest ~= "" then
        for k, _ in pairs(preset.param_defs) do
          local val = rest:match(k .. "%s*=%s*([^,)]+)")
          if val then
            params[k] = val:match("^%s*(.-)%s*$")
          end
        end
      end
      return preset.key, params
    end
  end
  return nil, nil
end

function M.preset_to_annotation(preset, params)
  if not preset.has_params or not params or not next(params) then
    return preset.annotation
  end
  local parts = {}
  for k, v in pairs(params) do
    table.insert(parts, k .. " = " .. v)
  end
  return preset.annotation .. "(" .. table.concat(parts, ", ") .. ")"
end

return M
