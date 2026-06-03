local M = {}

function M.setup(opts)
  local config = require("poja.config")
  config.setup(opts)
  local o = config.options

  require("poja.detect").setup(o)

  if o.creator.enabled then
    require("poja.creator").setup(o)
  end

  if o.ui.enabled then
    vim.api.nvim_create_user_command("PojaCreateAttribute", function()
      require("poja.ui").edit_fields()
    end, { desc = "Edit entity fields in a floating window" })
  end

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
