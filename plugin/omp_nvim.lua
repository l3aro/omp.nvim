-- omp.nvim entry: setup, commands, and turn-end file refresh.
require("omp_nvim").setup()

require("omp_nvim.bridge").on_status(function(event)
  if event == "turn_ended" then
    vim.cmd("checktime") -- reload files omp changed on disk; modified buffers are protected
  end
end)

-- :OmpAsk [instruction] — send a prompt to the omp in this directory.
-- Ranges send the current file's lines: :5,20OmpAsk, :%OmpAsk, :'<,'>OmpAsk.
vim.api.nvim_create_user_command("OmpAsk", function(args)
  local text = table.concat(args.fargs, " ")
  local omp = require("omp_nvim")
  local ok, err
  if args.range > 0 then
    ok, err = omp.send_range(args.line1, args.line2, text)
  elseif text ~= "" then
    ok, err = omp.prompt(text)
  else
    ok, err = omp.prompt(vim.fn.input("omp: "))
  end
  if not ok then
    vim.notify(err, vim.log.levels.WARN, { title = "omp.nvim" })
  end
end, { range = true, nargs = "*" })

-- :OmpNvimInstallExtension — (re)install the bridge into ~/.omp/agent/extensions.
vim.api.nvim_create_user_command("OmpNvimInstallExtension", function()
  require("omp_nvim").install_extension()
end, {})

-- Default keymaps; opt out with vim.g.omp_nvim_no_keymaps = true
if not vim.g.omp_nvim_no_keymaps then
  vim.keymap.set("n", "<leader>oa", function()
    vim.cmd("OmpAsk")
  end, { desc = "omp: ask" })
  vim.keymap.set("x", "<leader>oa", function()
    vim.cmd("'<,'>OmpAsk")
  end, { desc = "omp: ask selection" })
end
