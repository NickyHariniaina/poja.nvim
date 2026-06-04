local M = {}

function M.setup(opts)
  local config = require("poja.config")
  config.setup(opts)
  require("poja.detect").setup(config.options)

  if not vim.g.loaded_poja then
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

    vim.api.nvim_create_user_command("PojaCreateFK", function()
      require("poja.ui.fk").start()
    end, { desc = "Add entity FK relationship via prompts" })

    vim.api.nvim_create_user_command("PojaCreateRepositoryMethod", function()
      require("poja.ui.repository").start()
    end, { desc = "Add repository query method via prompts" })

    vim.api.nvim_create_user_command("PojaCreateFlywayEnumMigration", function()
      require("poja.ui.enum_migration").start()
    end, { desc = "Create Flyway migration for enum in current buffer" })
  end
end

return M
