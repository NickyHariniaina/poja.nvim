local M = {}

M.defaults = {
  detect = {
    enabled = true,
  },
  creator = {
    enabled = true,
  },
  ui = {
    enabled = true,
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
