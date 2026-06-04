local M = {}

M.poja_app_path = nil

local function find_poja_app()
  local cwd = vim.fn.getcwd()
  local files = vim.fn.glob(cwd .. "/src/main/java/**/PojaApplication.java", false, true)
  if #files == 0 then
    return nil
  end

  local content = vim.fn.readfile(files[1])
  for _, line in ipairs(content) do
    if line:find("@PojaGenerated", 1, true) then
      M.poja_app_path = files[1]
      return files[1]
    end
  end
  return nil
end

function M.setup(opts)
  if opts and opts.detect and opts.detect.enabled then
    find_poja_app()
  end
end

function M.is_poja_project()
  return M.poja_app_path ~= nil
end

function M.get_poja_app_path()
  return M.poja_app_path
end

return M
