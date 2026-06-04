local M = {}

local http_methods = { "GET", "POST", "PUT", "DELETE", "PATCH" }

local param_kinds = { "PathVariable", "RequestParam", "RequestBody", "RequestPart" }

local function annotation_for(method)
  if method == "GET" then return "GetMapping"
  elseif method == "POST" then return "PostMapping"
  elseif method == "PUT" then return "PutMapping"
  elseif method == "DELETE" then return "DeleteMapping"
  else return "PatchMapping" end
end

local function import_for(method)
  return "org.springframework.web.bind.annotation." .. annotation_for(method)
end

local function import_for_kind(kind)
  return "org.springframework.web.bind.annotation." .. kind
end

local function insert_endpoint(lines, method_info)
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
    vim.notify("poja: could not find insertion point", vim.log.levels.ERROR)
    return false
  end

  local indent = "  "
  for i = 1, insert_pos do
    local idt = lines[i]:match("^(%s+)")
    if idt then indent = idt; break end
  end

  local method_lines = {}

  local annotation = annotation_for(method_info.http_method)
  local path_str = ""
  if method_info.path and method_info.path ~= "" then
    path_str = "(\"" .. method_info.path .. "\")"
  end
  table.insert(method_lines, indent .. "@" .. annotation .. path_str)
  table.insert(method_lines, indent .. "public " .. method_info.return_type .. " " .. method_info.method_name .. "(")

  if #method_info.params > 0 then
    local param_strs = {}
    for _, p in ipairs(method_info.params) do
      local s = p.annotation_str
      local suffix = ""
      if p.required ~= nil then
        suffix = "(required = " .. tostring(p.required) .. ")"
        if p.default_value then
          suffix = "(required = " .. tostring(p.required) .. ", defaultValue = \"" .. p.default_value .. "\")"
        end
      elseif p.name_override then
        suffix = "(\"" .. p.name_override .. "\")"
      end
      s = "@" .. p.kind .. suffix .. " " .. p.java_type .. " " .. p.name
      table.insert(param_strs, s)
    end
    local separator = ",\n" .. indent .. "    "
    method_lines[#method_lines] = method_lines[#method_lines] .. separator .. table.concat(param_strs, separator)
  end

  method_lines[#method_lines] = method_lines[#method_lines] .. ") {"
  table.insert(method_lines, indent .. "    return \"\";")
  table.insert(method_lines, indent .. "}")

  local sep = lines[insert_pos]:match("%S") and { "" } or {}
  vim.api.nvim_buf_set_lines(bufnr, insert_pos, insert_pos, false, sep)
  vim.api.nvim_buf_set_lines(bufnr, insert_pos + #sep, insert_pos + #sep, false, method_lines)
  return true
end

local function prompt_params(collected, callback)
  vim.ui.select(param_kinds, {
    prompt = "Parameter kind:",
    format_item = function(item) return item end,
  }, function(kind)
    if not kind then
      callback(collected)
      return
    end

    vim.ui.input({ prompt = "Name: " }, function(name)
      if not name or name == "" then
        callback(collected)
        return
      end

      vim.ui.input({ prompt = "Java type (default String): " }, function(jtype)
        if not jtype or jtype == "" then jtype = "String" end
        local param = { kind = kind, name = name, java_type = jtype }

        if kind == "RequestParam" then
          vim.ui.input({ prompt = "Required? (y/n): " }, function(req)
            param.required = req and req:lower():sub(1, 1) == "y"
            vim.ui.input({ prompt = "Default value (empty = none): " }, function(dv)
              if dv and dv ~= "" then param.default_value = dv end
              maybe_more(collected, param, callback)
            end)
          end)
        elseif kind == "RequestPart" then
          vim.ui.input({ prompt = "Part name (default " .. name .. "): " }, function(pn)
            if pn and pn ~= "" and pn ~= name then param.name_override = pn end
            maybe_more(collected, param, callback)
          end)
        else
          maybe_more(collected, param, callback)
        end
      end)
    end)
  end)
end

local function maybe_more(collected, param, callback)
  table.insert(collected, param)
  vim.ui.input({ prompt = "More parameters? (y/n): " }, function(more)
    if more and more:lower():sub(1, 1) == "y" then
      prompt_params(collected, callback)
    else
      callback(collected)
    end
  end)
end

function M.start()
  local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if bufname == "" or not bufname:match("%.java$") then
    vim.notify("poja: not a Java file", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)

  vim.ui.input({ prompt = "Method name: " }, function(method_name)
    if not method_name or method_name == "" then return end

    vim.ui.select(http_methods, {
      prompt = "HTTP method:",
      format_item = function(item) return item end,
    }, function(http_method)
      if not http_method then return end

      vim.ui.input({ prompt = "Endpoint path (e.g. /students/{id}): " }, function(path)
        if not path then return end

        vim.ui.input({ prompt = "Return type (default String): " }, function(return_type)
          if not return_type or return_type == "" then return_type = "String" end

          prompt_params({}, function(params)
            local imports = {}
            imports[import_for(http_method)] = true
            local seen_kinds = {}
            for _, p in ipairs(params) do
              if not seen_kinds[p.kind] then
                imports[import_for_kind(p.kind)] = true
                seen_kinds[p.kind] = true
              end
            end

            local import_list = {}
            for imp, _ in pairs(imports) do
              table.insert(import_list, imp)
            end
            table.sort(import_list)

            local method_info = {
              method_name = method_name,
              http_method = http_method,
              path = path,
              return_type = return_type,
              params = params,
              imports = import_list,
            }

            insert_endpoint(lines, method_info)
            vim.notify("poja: added " .. http_method .. " " .. method_name, vim.log.levels.INFO)
          end)
        end)
      end)
    end)
  end)
end

return M
