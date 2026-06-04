local M = {}

local function entity_from_repo(lines)
  for _, line in ipairs(lines) do
    local entity = line:match("extends%s+JpaRepository%s*<%s*(%w+)%s*,")
    if entity then return entity end
  end
  return nil
end

local function entity_import_pkg(lines, entity_name)
  for _, line in ipairs(lines) do
    local pkg = line:match("^import%s+([^;]+)" .. entity_name .. ";%s*$")
    if pkg then return pkg end
  end
  return nil
end

local function find_entity_file(entity_name)
  local cwd = vim.fn.getcwd()
  local files = vim.fn.glob(cwd .. "/src/main/java/**/" .. entity_name .. ".java", false, true)
  if #files > 0 then return files[1] end
  return nil
end

local function entity_field_types(filepath)
  local content = vim.fn.readfile(filepath)
  local fields = {}
  for _, line in ipairs(content) do
    local typ, name = line:match("^%s*private%s+([%w%.<>%[%],%?%s]+)%s+(%w+)%s*[=;]")
    if typ and name then
      typ = typ:match("^%s*(.-)%s*$")
      fields[name] = typ
    end
  end
  return fields
end

local function field_type_to_param(fields, field_name, entity_name)
  local typ = fields[field_name]
  if typ then
    if typ == entity_name then
      return nil, "cannot reference self"
    end
    local needs_import = typ:match("%.")
    if needs_import then
      return typ:match("([%w.]+)$"), typ
    end
    return typ, nil
  end
  return nil, nil
end

local function make_return_type(prefix, entity_name)
  if prefix == "findBy" then return "Optional<" .. entity_name .. ">" end
  if prefix == "getBy" then return entity_name end
  if prefix == "existsBy" then return "boolean" end
  if prefix == "countBy" then return "long" end
  if prefix == "deleteBy" then return "void" end
  return entity_name
end

local function make_method_name(prefix, field_parts)
  local field_part = table.concat(field_parts, "And")
  return prefix .. field_part
end

local function make_param_str(field_parts, fields, entity_name)
  local params = {}
  for _, fname in ipairs(field_parts) do
    local typ = fields[fname]
    if not typ then typ = "String" end
    table.insert(params, typ .. " " .. fname)
  end
  return table.concat(params, ", ")
end

local function insert_method(lines, method_sig, imports)
  local bufnr = vim.api.nvim_get_current_buf()

  if imports and #imports > 0 then
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
    for _, imp in ipairs(imports) do
      local line = "import " .. imp .. ";"
      if not existing[line] then
        local pkg = imp:match("^(.*)%.[^%.]+$")
        local covered = false
        for wc, _ in pairs(wildcards) do
          if pkg and (pkg == wc or pkg:find(wc .. "%.", 1, true)) then
            covered = true
            break
          end
        end
        if not covered then
          table.insert(to_insert, line)
        end
      end
    end

    if #to_insert > 0 and last_import >= 0 then
      table.sort(to_insert)
      vim.api.nvim_buf_set_lines(bufnr, last_import, last_import, false, to_insert)
      lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end
  end

  local insert_pos
  local brace_depth = 0
  for i, line in ipairs(lines) do
    brace_depth = brace_depth + line:gsub("[^%{]", ""):len() - line:gsub("[^%}]", ""):len()
    if brace_depth == 0 and line:match("}%s*$") and i > 1 then
      insert_pos = i - 1
      break
    end
  end

  if not insert_pos then
    vim.notify("poja: could not find insertion point in repository", vim.log.levels.ERROR)
    return false
  end

  local indent = "  "
  for i = 1, insert_pos do
    local idt = lines[i]:match("^(%s+)")
    if idt then indent = idt; break end
  end

  local sep = lines[insert_pos]:match("%S") and { "" } or {}
  vim.api.nvim_buf_set_lines(bufnr, insert_pos, insert_pos, false, sep)
  vim.api.nvim_buf_set_lines(bufnr, insert_pos + #sep, insert_pos + #sep, false, { indent .. method_sig .. ";" })
  return true
end

local function prompt_prefix(callback)
  vim.ui.input({ prompt = "Prefix (findBy/getBy/existsBy/countBy/deleteBy) [findBy]: " }, function(input)
    local prefix = (input and input ~= "") and input or "findBy"
    callback(prefix)
  end)
end

local function prompt_field_name(idx, callback)
  local label = idx == 1 and "Field name" or "And field"
  vim.ui.input({ prompt = label .. ": " }, function(input)
    if not input or input == "" then
      callback(nil)
    else
      callback(input)
    end
  end)
end

local function prompt_more_fields(callback)
  vim.ui.input({ prompt = "More fields? (y/n): " }, function(input)
    callback(input and input:lower():sub(1, 1) == "y")
  end)
end

local function build_method(prefix, field_parts, fields, entity_name)
  local method_name = make_method_name(prefix, field_parts)
  local return_type = make_return_type(prefix, entity_name)
  local param_str = make_param_str(field_parts, fields, entity_name)

  local method = return_type .. " " .. method_name .. "(" .. param_str .. ")"

  local imports = {}
  if prefix == "findBy" then
    table.insert(imports, "java.util.Optional")
  end

  return method, imports
end

local function prompt_field_chain(prefix, fields, entity_name, field_parts)
  prompt_field_name(#field_parts + 1, function(fname)
    if not fname then
      if #field_parts == 0 then return end
      local method, imports = build_method(prefix, field_parts, fields, entity_name)
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
      insert_method(lines, method, imports)
      vim.notify("Added " .. method, vim.log.levels.INFO)
      return
    end

    table.insert(field_parts, fname)
    prompt_more_fields(function(more)
      if more then
        prompt_field_chain(prefix, fields, entity_name, field_parts)
      else
        local method, imports = build_method(prefix, field_parts, fields, entity_name)
        local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
        insert_method(lines, method, imports)
        vim.notify("Added " .. method, vim.log.levels.INFO)
      end
    end)
  end)
end

function M.start()
  local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if bufname == "" or not bufname:match("%.java$") then
    vim.notify("poja: not a Java file", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
  local entity_name = entity_from_repo(lines)
  if not entity_name then
    vim.notify("poja: not a repository file (no JpaRepository found)", vim.log.levels.ERROR)
    return
  end

  local fields = {}
  local entity_file = find_entity_file(entity_name)
  if entity_file then
    fields = entity_field_types(entity_file)
    vim.notify("Found entity: " .. entity_name .. " (" .. #vim.tbl_keys(fields) .. " fields)", vim.log.levels.INFO)
  else
    vim.notify("Entity file " .. entity_name .. ".java not found, using String for parameter types", vim.log.levels.WARN)
  end

  -- Pre-populate field names for inline hints
  local entity_fields = {}
  for fname, ftype in pairs(fields) do
    table.insert(entity_fields, fname .. ":" .. ftype)
  end

  prompt_prefix(function(prefix)
    if prefix ~= "findBy" and prefix ~= "getBy" and prefix ~= "existsBy" and prefix ~= "countBy" and prefix ~= "deleteBy" then
      vim.notify("poja: invalid prefix '" .. prefix .. "'", vim.log.levels.ERROR)
      return
    end
    prompt_field_chain(prefix, fields, entity_name, {})
  end)
end

return M
