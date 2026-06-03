local M = {}

function M.setup(opts)
  local config = require("poja.config")
  config.setup(opts)
  local o = config.options

  require("poja.detect").setup(o)

  vim.api.nvim_create_user_command("PojaApplication", function()
    local detect = require("poja.detect")
    if detect.is_poja_project() then
      vim.notify("Poja Application: " .. detect.get_poja_app_path(), vim.log.levels.INFO)
    else
      vim.notify("Not a Poja project", vim.log.levels.WARN)
    end
  end, { desc = "Show Poja Application class path" })
end

return M
