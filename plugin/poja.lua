if vim.g.loaded_poja then return end
vim.g.loaded_poja = true

vim.api.nvim_create_user_command("PojaApplication", function()
  local detect = require("poja.detect")
  if detect.is_poja_project() then
    vim.notify("Poja Application: " .. detect.get_poja_app_path(), vim.log.levels.INFO)
  else
    vim.notify("Not a Poja project", vim.log.levels.WARN)
  end
end, { desc = "Show Poja Application class path" })

vim.api.nvim_create_user_command("PojaCreate", function()
  require("poja.creator").create_interactive()
end, { desc = "Create a Poja-pattern Java file" })

vim.api.nvim_create_user_command("PojaCreateAttribute", function()
  require("poja.ui").edit_fields()
end, { desc = "Edit entity fields in a floating window" })
