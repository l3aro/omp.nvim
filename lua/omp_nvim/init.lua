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

---Text of the last visual selection / mark range.
---@param mode "'v'" | "'V'" | "'\\22'"
---@return string[]?
local function range_text(mode)
  local from = vim.fn.getpos("'<")
  local to = vim.fn.getpos("'>")
  if from[2] == 0 or to[2] == 0 then
    return nil
  end
  if vim.fn.has("nvim-0.11") == 1 then
    return vim.fn.getregion({ from[2], from[3] - 1 }, { to[2], to[3] - 1 }, { type = mode })
  end
  return vim.fn.getline(from[2], to[2])
end

---Send the current file with the selection/range as context.
---@param mode "'v'" | "'V'" | "'\\22'"
---@param extra? string Optional instruction prepended to the context.
---@return boolean ok
---@return string? err
function M.send_selection(mode, extra)
  local lines = range_text(mode)
  if not lines then
    return false, "no selection"
  end
  local file = vim.fn.expand("%")
  local text = table.concat(lines, "\n")
  if file ~= "" then
    text = string.format("%s:%d\n```\n%s\n```", file, vim.fn.line("'<"), text)
  end
  if extra and extra ~= "" then
    text = extra .. "\n\n" .. text
  end
  return M.prompt(text)
end

return M
