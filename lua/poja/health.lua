local M = {}

function M.check()
  vim.health.start("poja.nvim")

  local detect = require("poja.detect")
  if detect.is_poja_project() then
    vim.health.ok("Poja project detected at " .. detect.get_poja_app_path())
  else
    vim.health.info("Not in a Poja project (run :PojaApplication to verify)")
  end

  local ok_templates, templates = pcall(require, "poja.creator.templates")
  if ok_templates and next(templates) then
    local count = 0
    for _ in pairs(templates) do count = count + 1 end
    vim.health.ok(count .. " templates loaded")
  else
    vim.health.warn("No templates found")
  end

  local ok_parser, parser = pcall(require, "poja.ui.parser")
  if ok_parser and type(parser.parse_fields_from_buffer) == "function" then
    vim.health.ok("Field parser loaded")
  else
    vim.health.error("Field parser failed to load")
  end

  local ok_cmds, commands = pcall(vim.api.nvim_get_commands, {})
  local found = {}
  if ok_cmds then
    for name in pairs(commands) do
      if name:match("^Poja") then table.insert(found, name) end
    end
  end
  if #found > 0 then
    vim.health.ok("Commands registered: " .. table.concat(found, ", "))
  else
    vim.health.warn("No Poja commands registered")
  end
end

return M
