local templates = require("poja.creator.templates")

local function camel_case(name)
  return name:sub(1, 1):lower() .. name:sub(2)
end

local function snake_case(name)
  return name:gsub("([A-Z])", "_%1"):lower():gsub("^_", "")
end

local function detect_base_dir()
  local app_path = require("poja.detect").get_poja_app_path()
  if not app_path then return nil end
  local base_dir = app_path:match("(.+/)PojaApplication%.java$")
  if base_dir then base_dir = base_dir:gsub("/$", "") end
  return base_dir
end

local function detect_base_package()
  local base_dir = detect_base_dir()
  if not base_dir then return nil end
  local java_idx = base_dir:find("src/main/java/")
  if not java_idx then return nil end
  local pkg_path = base_dir:sub(java_idx + #"src/main/java/")
  return pkg_path:gsub("/", ".")
end

local function get_target_path(entry, class_name)
  local base_dir = detect_base_dir()
  if not base_dir then return nil end
  local dir = base_dir .. "/" .. entry.dir
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. class_name .. entry.suffix .. ".java"
end

local function render_template(entry, class_name)
  local tmpl = templates[entry.type]
  if not tmpl then return nil end
  local base_package = detect_base_package()
  if not base_package then return nil end
  local sub_pkg = entry.dir:gsub("/", ".")
  local full_package = base_package .. "." .. sub_pkg
  local result = tmpl
  result = result:gsub("%${PACKAGE}", full_package)
  result = result:gsub("%${BASE_PACKAGE}", base_package)
  result = result:gsub("%${NAME}", class_name)
  result = result:gsub("%${NAME_LOWER}", camel_case(class_name))
  result = result:gsub("%${TABLE}", snake_case(class_name))
  return result
end

return {
  render_template = render_template,
  get_target_path = get_target_path,
}
