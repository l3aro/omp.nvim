-- omp.nvim entry: setup, commands, and turn-end file refresh.
require("omp_nvim").setup()

require("omp_nvim.bridge").on_status(function(event)
  if event == "turn_ended" then
    vim.cmd("checktime") -- reload files omp changed on disk; modified buffers are protected
  end
end)

-- :OmpAsk [instruction] — send a prompt to the omp in this directory.
-- Ranges send the current file's lines: :5,20OmpAsk, :%OmpAsk, :'<,'>OmpAsk.
-- @placeholders in the instruction are NOT expanded on the range branch
-- (the range is the context); use the visual <leader>oa mapping instead.
vim.api.nvim_create_user_command("OmpAsk", function(args)
  local text = table.concat(args.fargs, " ")
  local omp = require("omp_nvim")
  local ok, err
  if args.range > 0 then
    ok, err = omp.send_range(args.line1, args.line2, text)
  else
    -- Snapshot before input: input() exits visual mode / moves the cursor.
    local ctx = require("omp_nvim.context").new()
    if text ~= "" then
      ok, err = omp.prompt(ctx:render(text))
    else
      -- Interactive prompt: Enter submits, Esc (or empty) discards.
      local input = vim.fn.input("omp: ")
      if input == nil or input == "" then
        return
      end
      ok, err = omp.prompt(ctx:render(input))
    end
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
    local ok, err = require("omp_nvim").ask()
    if not ok then
      vim.notify(err, vim.log.levels.WARN, { title = "omp.nvim" })
    end
  end, { desc = "omp: ask selection" })
end
