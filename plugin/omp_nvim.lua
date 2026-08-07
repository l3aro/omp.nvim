-- omp.nvim entry: setup, commands, and turn-end file refresh.
require("omp_nvim").setup()

require("omp_nvim.bridge").on_status(function(event)
  if event == "turn_ended" then
    vim.cmd("checktime") -- reload files omp changed on disk; modified buffers are protected
  end
end)

-- :OmpAsk [instruction] — send a prompt to the omp in this directory.
-- With a range (e.g. :'<,'>OmpAsk explain) sends the current file + range.
vim.api.nvim_create_user_command("OmpAsk", function(args)
  local text = table.concat(args.fargs, " ")
  local ok, err
  if args.range > 0 then
    ok, err = require("omp_nvim").send_selection("line", text)
  elseif text ~= "" then
    ok, err = require("omp_nvim").prompt(text)
  else
    ok, err = require("omp_nvim").prompt(vim.fn.input("omp: "))
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
