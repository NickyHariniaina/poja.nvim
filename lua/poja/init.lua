local M = {}

function M.setup(opts)
  require("poja.config").setup(opts)
  require("poja.detect").setup(opts)
end

return M
