local parser = require("poja.ui.parser")

local M = {}

local function entity_files(name)
  local cwd = vim.fn.getcwd()
  return vim.fn.glob(cwd .. "/src/main/java/**/" .. name .. ".java", false, true)
end

local function entity_package(filepath)
  local content = vim.fn.readfile(filepath, "", 10)
  for _, line in ipairs(content) do
    local pkg = line:match("^package%s+([^;]+);")
    if pkg then return pkg end
  end
  return nil
end

local function make_field_name(name)
  return name:sub(1,1):lower() .. name:sub(2)
end

local function make_join_col(name)
  local snake = name:gsub("([a-z])([A-Z])", "%1_%2"):gsub("([A-Z])([A-Z][a-z])", "%1_%2"):lower()
  return snake .. "_id"
end

local function pluralize(name)
  return name .. "s"
end

local function needed_imports(imports)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

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
    -- re-read lines after modification
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end

  return lines
end

local function insert_fk_block(lines, annotations, field_type, field_name, imports)
  local bufnr = vim.api.nvim_get_current_buf()
  lines = needed_imports(imports)

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

  local block = {}
  for _, a in ipairs(annotations) do
    for line in a:gmatch("[^\n]+") do
      table.insert(block, indent .. line)
    end
  end
  table.insert(block, indent .. "private " .. field_type .. " " .. field_name .. ";")

  local sep = field_end > 0 and lines[field_end]:match("%S") and { "" } or {}
  vim.api.nvim_buf_set_lines(bufnr, field_end, field_end, false, sep)
  local new_end = field_end + #sep
  vim.api.nvim_buf_set_lines(bufnr, new_end, new_end, false, block)
  return true
end

local function prompt_field_name(entity_name, callback)
  vim.ui.input({ prompt = "Field name (" .. make_field_name(entity_name) .. "): " }, function(input)
    local name = (input and input ~= "") and input or make_field_name(entity_name)
    callback(name)
  end)
end

local function prompt_fetch(callback)
  vim.ui.input({ prompt = "Fetch (LAZY/EAGER) [LAZY]: " }, function(input)
    local f = (input and input ~= "") and input or "LAZY"
    callback(f)
  end)
end

local function prompt_join_col(entity_name, callback)
  local default = make_join_col(entity_name)
  vim.ui.input({ prompt = "JoinColumn name (" .. default .. "): " }, function(input)
    local col = (input and input ~= "") and input or default
    callback(col)
  end)
end

local function prompt_nullable(callback)
  vim.ui.input({ prompt = "nullable? (y/n) [n]: " }, function(input)
    callback(input and input:lower():sub(1, 1) == "y")
  end)
end

local function prompt_updatable(callback)
  vim.ui.input({ prompt = "updatable? (y/n) [n]: " }, function(input)
    callback(input and input:lower():sub(1, 1) == "y")
  end)
end

local function prompt_mapped_by(entity_name, callback)
  local default = make_field_name(entity_name)
  vim.ui.input({ prompt = "mappedBy (" .. default .. "): " }, function(input)
    local mb = (input and input ~= "") and input or default
    callback(mb)
  end)
end

local function prompt_many_to_one(entity_name, entity_pkg)
  prompt_field_name(entity_name, function(field_name)
    prompt_fetch(function(fetch)
      prompt_join_col(entity_name, function(join_col)
        prompt_nullable(function(nullable)
          prompt_updatable(function(updatable)
            local imports = { "jakarta.persistence.ManyToOne", "jakarta.persistence.JoinColumn", "jakarta.persistence.FetchType" }
            if entity_pkg then table.insert(imports, entity_pkg .. "." .. entity_name) end

            local annots = { "@ManyToOne(fetch = FetchType." .. fetch .. ")" }
            local jc_parts = { "name = \"" .. join_col .. "\"" }
            if not nullable then table.insert(jc_parts, "nullable = false") end
            if not updatable then table.insert(jc_parts, "updatable = false") end
            annots[#annots + 1] = "@JoinColumn(" .. table.concat(jc_parts, ", ") .. ")"

            local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
            local ok = insert_fk_block(lines, annots, entity_name, field_name, imports)
            if ok then
              vim.notify("Added @ManyToOne " .. field_name .. ": " .. entity_name, vim.log.levels.INFO)
            end
          end)
        end)
      end)
    end)
  end)
end

local function prompt_one_to_one(entity_name, entity_pkg)
  prompt_field_name(entity_name, function(field_name)
    prompt_join_col(entity_name, function(join_col)
      local imports = { "jakarta.persistence.OneToOne", "jakarta.persistence.JoinColumn" }
      if entity_pkg then table.insert(imports, entity_pkg .. "." .. entity_name) end

      local annots = { "@OneToOne" }
      annots[#annots + 1] = "@JoinColumn(name = \"" .. join_col .. "\", unique = true)"

      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
      local ok = insert_fk_block(lines, annots, entity_name, field_name, imports)
      if ok then
        vim.notify("Added @OneToOne " .. field_name .. ": " .. entity_name, vim.log.levels.INFO)
      end
    end)
  end)
end

local function prompt_one_to_many(entity_name, entity_pkg)
  local default_name = pluralize(make_field_name(entity_name))
  vim.ui.input({ prompt = "Field name (" .. default_name .. "): " }, function(field_input)
    local field_name = (field_input and field_input ~= "") and field_input or default_name

    prompt_mapped_by(entity_name, function(mapped_by)
      prompt_fetch(function(fetch)
        local field_type = "List<" .. entity_name .. ">"
        local imports = { "jakarta.persistence.OneToMany", "jakarta.persistence.FetchType" }
        if entity_pkg then table.insert(imports, entity_pkg .. "." .. entity_name) end

        local fetch_part = ", fetch = FetchType." .. fetch
        local annot = "@OneToMany(mappedBy = \"" .. mapped_by .. "\"" .. fetch_part .. ")"
        local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
        local ok = insert_fk_block(lines, { annot }, field_type, field_name, imports)
        if ok then
          vim.notify("Added @OneToMany " .. field_name .. ": " .. entity_name, vim.log.levels.INFO)
        end
      end)
    end)
  end)
end

local function prompt_many_to_many(entity_name, entity_pkg)
  local default_name = pluralize(make_field_name(entity_name))
  vim.ui.input({ prompt = "Field name (" .. default_name .. "): " }, function(field_input)
    local field_name = (field_input and field_input ~= "") and field_input or default_name

    vim.ui.input({ prompt = "Owning side? (y/n) [y]: " }, function(owning_input)
      local owning = not owning_input or owning_input:lower():sub(1, 1) ~= "n"
      local field_type = "List<" .. entity_name .. ">"
      local imports = { "jakarta.persistence.ManyToMany", "jakarta.persistence.FetchType" }
      if entity_pkg then table.insert(imports, entity_pkg .. "." .. entity_name) end

      if owning then
        prompt_fetch(function(fetch)
          local fetch_part = "fetch = FetchType." .. fetch
          local annot = "@ManyToMany(" .. fetch_part .. ")\n@JoinTable(name = \"" .. make_join_col(entity_name) .. "\")"
          local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
          local ok = insert_fk_block(lines, { annot }, field_type, field_name, imports)
          if ok then
            vim.notify("Added @ManyToMany (owning) " .. field_name .. ": " .. entity_name, vim.log.levels.INFO)
          end
        end)
      else
        prompt_mapped_by(entity_name, function(mapped_by)
          local annot = "@ManyToMany(mappedBy = \"" .. mapped_by .. "\")"
          local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
          local ok = insert_fk_block(lines, { annot }, field_type, field_name, imports)
          if ok then
            vim.notify("Added @ManyToMany (inverse) " .. field_name .. ": " .. entity_name, vim.log.levels.INFO)
          end
        end)
      end
    end)
  end)
end

local function prompt_relation_type(entity_name, entity_pkg)
  vim.ui.input({ prompt = "ManyToOne? (y/n): " }, function(input)
    if input and input:lower():sub(1, 1) == "y" then
      prompt_many_to_one(entity_name, entity_pkg)
      return
    end
    vim.ui.input({ prompt = "OneToOne? (y/n): " }, function(input2)
      if input2 and input2:lower():sub(1, 1) == "y" then
        prompt_one_to_one(entity_name, entity_pkg)
        return
      end
      vim.ui.input({ prompt = "OneToMany? (y/n): " }, function(input3)
        if input3 and input3:lower():sub(1, 1) == "y" then
          prompt_one_to_many(entity_name, entity_pkg)
          return
        end
        vim.ui.input({ prompt = "ManyToMany? (y/n): " }, function(input4)
          if input4 and input4:lower():sub(1, 1) == "y" then
            prompt_many_to_many(entity_name, entity_pkg)
          end
        end)
      end)
    end)
  end)
end

function M.start()
  local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if bufname == "" or not bufname:match("%.java$") then
    vim.notify("poja: not a Java file", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Related entity: " }, function(entity_name)
    if not entity_name or entity_name == "" then return end

    local files = entity_files(entity_name)
    if #files == 0 then
      vim.ui.input({ prompt = "Entity '" .. entity_name .. "' not found. Continue? (y/n): " }, function(input)
        if input and input:lower():sub(1, 1) == "y" then
          prompt_relation_type(entity_name, nil)
        end
      end)
    else
      local pkg = entity_package(files[1])
      vim.notify("Found: " .. files[1], vim.log.levels.INFO)
      prompt_relation_type(entity_name, pkg)
    end
  end)
end

return M
