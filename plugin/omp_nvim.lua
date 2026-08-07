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
  local notify_err = function(ok, err)
    if not ok then
      vim.notify(err, vim.log.levels.WARN, { title = "omp.nvim" })
    end
  end
  if args.range > 0 then
    notify_err(omp.send_range(args.line1, args.line2, text))
  else
    -- Snapshot before input: input() exits visual mode / moves the cursor.
    local ctx = require("omp_nvim.context").new()
    if text ~= "" then
      notify_err(omp.prompt(ctx:render(text)))
    else
      -- Floating dialog: Enter submits, Esc (or empty) discards.
      omp.input_dialog("omp: ", function(input, mode)
        if not input or input == "" then
          return
        end
        notify_err(omp.prompt(ctx:render(input), mode == "hold" and { submit = false } or nil))
      end)
    end
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
    require("omp_nvim").ask()
  end, { desc = "omp: ask selection" })
  vim.keymap.set("n", "<leader>oA", function()
    require("omp_nvim").ask({ hold = true })
  end, { desc = "omp: ask & hold (fill omp input, Enter there to run)" })
  vim.keymap.set("x", "<leader>oA", function()
    require("omp_nvim").ask({ hold = true })
  end, { desc = "omp: ask selection & hold" })
end
