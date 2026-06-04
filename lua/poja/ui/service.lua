local M = {}

local method_types = {
  { key = "getById" },
  { key = "findAll" },
  { key = "saveAll" },
  { key = "crupdate" },
  { key = "deleteById" },
  { key = "getByField" },
}

local function detect_entity(lines)
  for _, line in ipairs(lines) do
    local entity = line:match("private%s+final%s+(%w+)Repository%s+")
    if entity then return entity end
  end
  return nil
end

local function repo_variable(lines, entity_lower)
  for _, line in ipairs(lines) do
    local name = line:match("private%s+final%s+%w+Repository%s+(%w+)%s*;")
    if name then return name end
  end
  return entity_lower .. "Repository"
end

local function detect_base_pkg(lines)
  for _, line in ipairs(lines) do
    local pkg = line:match("^package%s+([^;]+);")
    if pkg then
      return pkg:match("(.+)%.[^%.]+$") or pkg
    end
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

local function make_method(method_key, entity_name, entity_lower, repo_var, base_pkg, field_name, field_type)
  local not_found_exc = (base_pkg or "school.hei.haapi") .. ".model.exception.NotFoundException"

  if method_key == "getById" then
    return {
      sig = "public " .. entity_name .. " getById(String id)",
      body = {
        "return " .. repo_var .. ".findById(id)",
        "    .orElseThrow(() -> new NotFoundException(\"" .. entity_name .. " with id \" + id + \" not found\"));",
      },
      imports = { not_found_exc },
    }
  end

  if method_key == "findAll" then
    return {
      sig = "public List<" .. entity_name .. "> findAll()",
      body = {
        "return " .. repo_var .. ".findAll();",
      },
      imports = { "java.util.List" },
    }
  end

  if method_key == "saveAll" then
    return {
      sig = "@Transactional\npublic List<" .. entity_name .. "> saveAll(List<" .. entity_name .. "> toSave)",
      body = {
        entity_lower .. "Validator.accept(toSave);",
        "return " .. repo_var .. ".saveAll(toSave);",
      },
      imports = {
        "java.util.List",
        "jakarta.transaction.Transactional",
        not_found_exc,
      },
    }
  end

  if method_key == "crupdate" then
    return {
      sig = "@Transactional\npublic " .. entity_name .. " crupdate(" .. entity_name .. " domain)",
      body = {
        "return " .. repo_var .. ".save(domain);",
      },
      imports = { "jakarta.transaction.Transactional" },
    }
  end

  if method_key == "deleteById" then
    return {
      sig = "public " .. entity_name .. " deleteById(String id)",
      body = {
        entity_name .. " " .. entity_lower .. " = getById(id);",
        repo_var .. ".delete(" .. entity_lower .. ");",
        "return " .. entity_lower .. ";",
      },
      imports = {},
    }
  end

  if method_key == "getByField" and field_name then
    local typ = field_type or "String"
    local field_cap = field_name:sub(1, 1):upper() .. field_name:sub(2)
    return {
      sig = "public " .. entity_name .. " getBy" .. field_cap .. "(" .. typ .. " " .. field_name .. ")",
      body = {
        "return " .. repo_var .. ".findBy" .. field_cap .. "(" .. field_name .. ")",
        "    .orElseThrow(() -> new NotFoundException(\"" .. entity_name .. " with " .. field_name .. " \" + " .. field_name .. " + \" not found\"));",
      },
      imports = { not_found_exc },
    }
  end

  return nil
end

local function insert_method(lines, method_info)
  local bufnr = vim.api.nvim_get_current_buf()

  if method_info.imports and #method_info.imports > 0 then
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
    for _, imp in ipairs(method_info.imports) do
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
    vim.notify("poja: could not find insertion point in service", vim.log.levels.ERROR)
    return false
  end

  local indent = "  "
  for i = 1, insert_pos do
    local idt = lines[i]:match("^(%s+)")
    if idt then indent = idt; break end
  end

  local method_lines = {}
  for sig_line in method_info.sig:gmatch("[^\n]+") do
    table.insert(method_lines, indent .. sig_line)
  end
  method_lines[#method_lines] = method_lines[#method_lines] .. " {"

  for _, bl in ipairs(method_info.body) do
    table.insert(method_lines, indent .. "  " .. bl)
  end
  table.insert(method_lines, indent .. "}")

  local sep = lines[insert_pos]:match("%S") and { "" } or {}
  vim.api.nvim_buf_set_lines(bufnr, insert_pos, insert_pos, false, sep)
  vim.api.nvim_buf_set_lines(bufnr, insert_pos + #sep, insert_pos + #sep, false, method_lines)
  return true
end

local function prompt_method_type(callback)
  vim.ui.select(method_types, {
    prompt = "Select service method type:",
    format_item = function(item) return item.key end,
  }, function(choice)
    callback(choice and choice.key)
  end)
end

local function prompt_field_name(fields, callback)
  local field_names = {}
  for name, typ in pairs(fields) do
    table.insert(field_names, { name = name, type = typ })
  end
  table.sort(field_names, function(a, b) return a.name < b.name end)

  if #field_names > 0 then
    vim.ui.select(field_names, {
      prompt = "Select field:",
      format_item = function(item) return item.name .. ": " .. item.type end,
    }, function(choice)
      callback(choice and choice.name, choice and choice.type)
    end)
  else
    vim.ui.input({ prompt = "Field name: " }, function(input)
      if input and input ~= "" then
        callback(input, "String")
      else
        callback(nil)
      end
    end)
  end
end

function M.start()
  local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if bufname == "" or not bufname:match("%.java$") then
    vim.notify("poja: not a Java file", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
  local entity_name = detect_entity(lines)
  if not entity_name then
    vim.notify("poja: not a service file (no Repository field found)", vim.log.levels.ERROR)
    return
  end

  local entity_lower = entity_name:sub(1, 1):lower() .. entity_name:sub(2)
  local repo_var = repo_variable(lines, entity_lower)
  local base_pkg = detect_base_pkg(lines)

  local fields = {}
  local entity_file = find_entity_file(entity_name)
  if entity_file then
    fields = entity_field_types(entity_file)
    local count = 0
    for _, _ in pairs(fields) do count = count + 1 end
    vim.notify("Found entity: " .. entity_name .. " (" .. count .. " fields)", vim.log.levels.INFO)
  else
    vim.notify("Entity file " .. entity_name .. ".java not found", vim.log.levels.WARN)
  end

  prompt_method_type(function(method_key)
    if not method_key then return end

    if method_key == "getByField" then
      prompt_field_name(fields, function(field_name, field_type)
        if not field_name then return end
        local method = make_method(method_key, entity_name, entity_lower, repo_var, base_pkg, field_name, field_type)
        if method then
          insert_method(lines, method)
          vim.notify("poja: added " .. method_key, vim.log.levels.INFO)
        end
      end)
    else
      local method = make_method(method_key, entity_name, entity_lower, repo_var, base_pkg)
      if method then
        insert_method(lines, method)
        vim.notify("poja: added " .. method_key, vim.log.levels.INFO)
      end
    end
  end)
end

return M
