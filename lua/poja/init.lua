local M = {}

function M.setup(opts)
  local config = require("poja.config")
  config.setup(opts)
  require("poja.detect").setup(config.options)
end

return M
