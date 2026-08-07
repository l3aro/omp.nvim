---:checkhealth omp_nvim
local M = {}

function M.check()
  local health = vim.health
  health.start("omp.nvim")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("nvim >= 0.11 (vim.uv pipe transport, vim.pack setup)")
  else
    health.error("nvim 0.11+ required (vim.uv pipe transport)")
    return
  end

  local ext = vim.fn.expand("~/.omp/agent/extensions/omp-nvim-bridge.ts")
  if vim.fn.filereadable(ext) == 1 then
    health.ok("bridge extension installed: " .. ext)
  else
    health.warn("bridge extension missing — installing now (restart omp instances to load it)")
    require("omp_nvim").install_extension()
  end

  local bridge = require("omp_nvim.bridge")
  local sock = bridge.socket_path(vim.fn.getcwd())
  local stat = vim.uv.fs_stat(sock)
  if stat and stat.type == "socket" then
    health.ok("bridge socket alive for " .. vim.fn.getcwd())
  else
    health.warn(
      "no omp bridge in "
        .. vim.fn.getcwd()
        .. " — start omp here (or restart a running one to load the extension); expected socket: "
        .. sock
    )
  end
end

return M
