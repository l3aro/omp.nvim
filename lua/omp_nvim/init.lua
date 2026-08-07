---omp.nvim public API.
---Sends editor context into the omp instance running in the current directory.
local M = {}

local bridge = require("omp_nvim.bridge")

---Directory containing the bundled bridge extension.
---@return string
local function repo_root()
  local src = debug.getinfo(1, "S").source -- @<root>/lua/omp_nvim/init.lua
  return vim.fn.fnamemodify(src:sub(2), ":h:h:h")
end

---Install (or refresh) the bridge extension into ~/.omp/agent/extensions/,
---where every omp auto-discovers it. Idempotent; returns true when written.
---@return boolean installed
function M.install_extension()
  local ext_dir = vim.fn.expand("~") .. "/.omp/agent/extensions"
  local target = ext_dir .. "/omp-nvim-bridge.ts"
  local bundled = repo_root() .. "/extension/omp-nvim-bridge.ts"
  if vim.fn.filereadable(bundled) == 0 then
    vim.notify("omp.nvim: bundled extension missing at " .. bundled, vim.log.levels.ERROR, {
      title = "omp.nvim",
    })
    return false
  end
  vim.fn.mkdir(ext_dir, "p")
  local want = vim.fn.join(vim.fn.readfile(bundled), "\n")
  if vim.fn.filereadable(target) == 1
    and vim.fn.join(vim.fn.readfile(target), "\n") == want then
    return false
  end
  vim.fn.writefile(vim.split(want, "\n", { plain = true }), target)
  vim.notify(
    "omp.nvim: bridge extension installed to " .. target
      .. " (restart running omp instances to load it)",
    vim.log.levels.INFO,
    { title = "omp.nvim" }
  )
  return true
end

---Set up omp.nvim. Installs the bridge extension so omp instances in any
---directory pick it up on their next start.
---@param _opts? table Unused; reserved for future configuration.
function M.setup(_opts)
  M.install_extension()
end

---Inject a prompt into the omp session running in the current directory.
---@param text string
---@return boolean ok
---@return string? err
function M.prompt(text)
  return bridge.prompt(text)
end

---Send the current file with lines [from, to] as context.
---@param from integer 1-based first line
---@param to integer 1-based last line
---@param extra? string Optional instruction prepended to the context.
---@return boolean ok
---@return string? err
function M.send_range(from, to, extra)
  if from > to then
    from, to = to, from
  end
  local lines = vim.fn.getline(from, to)
  if #lines == 0 then
    return false, "empty range"
  end
  local file = vim.fn.expand("%")
  local text = table.concat(lines, "\n")
  if file ~= "" then
    text = string.format("%s:%d-%d\n```\n%s\n```", file, from, to, text)
  end
  if extra and extra ~= "" then
    text = extra .. "\n\n" .. text
  end
  return M.prompt(text)
end

---Send the last visual selection as context.
---@param _mode string Unused; line-based.
---@param extra? string Optional instruction prepended to the context.
---@return boolean ok
---@return string? err
function M.send_selection(_mode, extra)
  local from = vim.fn.getpos("'<")
  local to = vim.fn.getpos("'>")
  if from[2] == 0 or to[2] == 0 then
    return false, "no selection"
  end
  return M.send_range(from[2], to[2], extra)
end

return M
