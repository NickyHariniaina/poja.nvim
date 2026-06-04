local M = {}

local function to_snake_case(name)
  return name:gsub("([%l])([%u])", "%1_%2"):lower()
end

local function parse_enums(lines)
  local enums = {}
  local current_enum = nil
  local collecting_values = false
  local current_class = nil
  local class_open_depth = nil
  local brace_depth = 0

  for _, line in ipairs(lines) do
    local opens = line:gsub("[^%{]", ""):len()
    local closes = line:gsub("[^%}]", ""):len()

    local cls = line:match("^%s*public%s+class%s+(%w+)")
    if cls then
      current_class = cls
      class_open_depth = brace_depth
    end

    local enum_name = line:match("^%s*public%s+enum%s+(%w+)")
    if enum_name then
      current_enum = {
        name = enum_name,
        class_name = current_class,
        values = {},
        seen_semicolon = false,
      }
      collecting_values = true
      goto continue
    end

    if collecting_values then
      if line:match("^%s*[}]%s*$") then
        if #current_enum.values > 0 then
          table.insert(enums, current_enum)
        end
        collecting_values = false
        current_enum = nil
        goto continue
      elseif not current_enum.seen_semicolon then
        local const = line:match("^%s*([%w_]+)")
        if const then
          const = const:gsub("[,;]$", "")
          if const ~= "" then
            table.insert(current_enum.values, const)
          end
        end
        if line:find(";") then
          current_enum.seen_semicolon = true
        end
      end
    end

    ::continue::
    brace_depth = brace_depth + opens - closes

    if current_class and class_open_depth and brace_depth <= class_open_depth then
      current_class = nil
      class_open_depth = nil
    end
  end

  return enums
end

local function find_migration_dir()
  local detect = require("poja.detect")
  if not detect.is_poja_project() then
    return nil
  end

  local app_path = detect.get_poja_app_path()
  local base = app_path:match("(.+)src/main/java/")
  if not base then return nil end

  return base .. "src/main/resources/db/migration/"
end

local function next_migration_version(migration_dir)
  local max_major, max_minor = 0, 0

  local ok, entries = pcall(vim.fn.readdir, migration_dir)
  if ok then
    for _, name in ipairs(entries) do
      local major, minor = name:match("^V(%d+)_(%d+)__")
      if major and minor then
        major, minor = tonumber(major), tonumber(minor)
        if major > max_major or (major == max_major and minor > max_minor) then
          max_major, max_minor = major, minor
        end
      end
    end
  end

  if max_major == 0 and max_minor == 0 then
    return { major = 1, minor = 1 }
  end

  return { major = max_major, minor = max_minor + 1 }
end

local function generate_sql(enum_info)
  local values_str = table.concat(enum_info.values, "', '")
  return string.format([[DO
$$
    BEGIN
        IF NOT EXISTS(SELECT FROM pg_type WHERE typname = '%s') THEN
            CREATE TYPE "%s" AS ENUM ('%s');
        END IF;
    END
$$;
]], enum_info.sql_name, enum_info.sql_name, values_str)
end

local function build_sql_name(enum_info)
  if enum_info.class_name then
    return to_snake_case(enum_info.class_name .. "_" .. enum_info.name)
  end
  return to_snake_case(enum_info.name)
end

local function format_enum_label(enum_info)
  local prefix = ""
  if enum_info.class_name then
    prefix = enum_info.class_name .. "."
  end
  return prefix .. enum_info.name .. " (" .. #enum_info.values .. " values)"
end

local function create_migration(enum_info)
  enum_info.sql_name = build_sql_name(enum_info)

  local migration_dir = find_migration_dir()
  if not migration_dir then
    vim.notify("poja: not a Poja project (no PojaApplication.java found)", vim.log.levels.ERROR)
    return
  end

  vim.fn.mkdir(migration_dir, "p")

  local version = next_migration_version(migration_dir)
  local filename = string.format("V%d_%d__Create_%s_enum.sql", version.major, version.minor, enum_info.sql_name)
  local filepath = migration_dir .. filename

  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("poja: migration file already exists: " .. filename, vim.log.levels.WARN)
    return
  end

  local sql = generate_sql(enum_info)
  local io = io
  local file, err = io.open(filepath, "w")
  if not file then
    vim.notify("poja: failed to write " .. filename .. " (" .. tostring(err) .. ")", vim.log.levels.ERROR)
    return
  end
  file:write(sql)
  file:close()

  vim.notify("poja: created " .. filename, vim.log.levels.INFO)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
end

function M.start()
  local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  if bufname == "" or not bufname:match("%.java$") then
    vim.notify("poja: not a Java file", vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
  local enums = parse_enums(lines)

  if #enums == 0 then
    vim.notify("poja: no enums found in current file", vim.log.levels.ERROR)
    return
  end

  if #enums == 1 then
    create_migration(enums[1])
  else
    vim.ui.select(enums, {
      prompt = "Select enum for migration:",
      format_item = format_enum_label,
    }, function(choice)
      if choice then create_migration(choice) end
    end)
  end
end

return M
