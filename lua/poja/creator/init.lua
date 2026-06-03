local render = require("poja.creator.render")

local types = {
  { label = "Entity",        type = "entity",        dir = "model",                  suffix = "" },
  { label = "Controller",    type = "controller",    dir = "endpoint/rest/controller", suffix = "Controller" },
  { label = "Service",       type = "service",       dir = "service",                suffix = "Service" },
  { label = "Repository",    type = "repository",    dir = "repository",             suffix = "Repository" },
  { label = "Mapper",        type = "mapper",        dir = "endpoint/rest/mapper",    suffix = "Mapper" },
  { label = "Event",         type = "event",         dir = "endpoint/event/model",    suffix = "Event" },
  { label = "Event Handler", type = "event_handler", dir = "service/event",           suffix = "Service" },
  { label = "DAO",           type = "dao",           dir = "repository/dao",          suffix = "Dao" },
  { label = "Validator",     type = "validator",     dir = "model/validator",         suffix = "Validator" },
  { label = "Exception",     type = "exception",     dir = "model/exception",         suffix = "Exception" },
  { label = "DTO",           type = "dto",           dir = "model/dto",               suffix = "Dto" },
}

local M = {}

function M.create(type_name, class_name)
  local entry
  for _, t in ipairs(types) do
    if t.type == type_name then
      entry = t
      break
    end
  end
  if not entry then
    vim.notify("poja: unknown type '" .. type_name .. "'", vim.log.levels.ERROR)
    return
  end

  local content = render.render_template(entry, class_name)
  if not content then
    vim.notify("poja: not in a Poja project", vim.log.levels.WARN)
    return
  end

  local filepath = render.get_target_path(entry, class_name)
  if not filepath then
    vim.notify("poja: could not determine target path", vim.log.levels.ERROR)
    return
  end

  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("poja: " .. filepath .. " already exists", vim.log.levels.WARN)
    return
  end

  local file = io.open(filepath, "w")
  if not file then
    vim.notify("poja: could not create " .. filepath, vim.log.levels.ERROR)
    return
  end
  file:write(content)
  file:close()

  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  vim.notify("poja: created " .. filepath, vim.log.levels.INFO)
end

function M.create_interactive()
  if not require("poja.detect").is_poja_project() then
    vim.notify("poja: not in a Poja project", vim.log.levels.WARN)
    return
  end

  vim.ui.select(types, {
    prompt = "Poja — Select type:",
    format_item = function(item)
      return item.label
    end,
  }, function(entry)
    if not entry then return end
    vim.ui.input({ prompt = "Class name: " }, function(name)
      if not name or name == "" then return end
      M.create(entry.type, name)
    end)
  end)
end

return M
