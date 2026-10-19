---omp.nvim public API.
---Sends editor context into the omp instance running in the current directory.
local M = {}

local bridge = require("omp_nvim.bridge")
local context = require("omp_nvim.context")

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
  local ext_dir = bridge.config_root .. "/agent/extensions"
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
  if vim.fn.filereadable(target) == 1 and vim.fn.join(vim.fn.readfile(target), "\n") == want then
    return false
  end
  vim.fn.writefile(vim.split(want, "\n", { plain = true }), target)
  vim.notify(
    "omp.nvim: bridge extension installed to " .. target .. " (restart running omp instances to load it)",
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
---@param opts? { submit?: boolean } Pass { submit = false } to fill omp's input
---editor without submitting; press Enter there to run.
---@return boolean ok
---@return string? err
function M.prompt(text, opts)
  return bridge.prompt(text, opts and opts.submit)
end

---Send the current file with lines [from, to] as context. Named, unmodified
---buffers reference the file (path:start-end); buffers with unsaved changes
---are snapshotted to a temp file; unnamed buffers inline the lines.
---@param from integer 1-based first line
---@param to integer 1-based last line
---@param extra? string Optional instruction prepended to the context.
---@return boolean ok
---@return string? err
function M.send_range(from, to, extra)
  if from > to then
    from, to = to, from
  end
  local text = context.range_reference(vim.fn.bufnr("%"), from, to)
  if text == "" then
    return false, "empty range"
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

---Interactive input dialog in a floating prompt buffer.
---Enter submits; Esc/Ctrl-C discards. Pass { hold = true } to make Enter
---fill omp's input without submitting instead (press Enter in omp to run).
---Callback fires with (text, mode) — mode is "submit"|"hold" — or
---(nil, nil) when cancelled.
---@param prompt string
---@param cb fun(text: string?, mode: "submit"|"hold"|nil)
---@param opts? { hold?: boolean } When true, Enter holds (mode is always "hold").
function M.input_dialog(prompt, cb, opts)
  local hold = opts and opts.hold
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "prompt"
  vim.bo[buf].bufhidden = "wipe"
  vim.fn.prompt_setprompt(buf, prompt)
  local ok, win = pcall(vim.api.nvim_open_win, buf, true, {
    relative = "editor",
    row = math.max(0, vim.o.lines - 3),
    col = 2,
    width = math.max(20, vim.o.columns - 4),
    height = 1,
    style = "minimal",
    border = "rounded",
  })
  if not ok then
    vim.api.nvim_buf_delete(buf, { force = true })
    return cb(nil, nil)
  end
  local done = false
  local function finish(mode, line)
    if done then
      return
    end
    done = true
    local text
    if mode then
      local prefix = vim.fn.prompt_getprompt(buf)
      text = line:sub(#prefix + 1)
    end
    pcall(vim.api.nvim_win_close, win, true)
    cb(text, mode)
  end
  vim.keymap.set("i", "<CR>", function()
    finish(hold and "hold" or "submit", vim.fn.getline(1))
  end, { buffer = buf })
  vim.keymap.set("i", "<Esc>", function()
    finish(nil)
  end, { buffer = buf })
  vim.fn.prompt_setinterrupt(buf, function()
    finish(nil)
  end)
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      finish(nil) -- window closed externally (e.g. :q): cancel
    end,
  })
  vim.cmd("startinsert")
end

---Ask interactively. Snapshots the current visual selection first (keeps
---char/block column precision that a '<,'> command range loses), then
---prompts with @this/@buffer resolved. Enter submits; Esc/empty discards.
---Pass { hold = true } to fill omp's input without submitting instead.
---@param opts? { hold?: boolean }
---@return boolean ok Always true; the dialog is asynchronous.
function M.ask(opts)
  local ctx = context.new() -- must run while still in visual mode
  M.input_dialog("omp: ", function(input, mode)
    if not input or input == "" then
      return -- discarded by the user
    end
    -- Auto-attach the captured selection unless the prompt is already
    -- explicit about context (@placeholders); matches '<,'> range behavior.
    if ctx.range and not input:find("@", 1, true) then
      local this = ctx:this()
      if this then
        input = input .. "\n\n" .. this
      end
    end
    local ok, err = M.prompt(ctx:render(input), mode == "hold" and { submit = false } or nil)
    if not ok then
      vim.notify(err, vim.log.levels.WARN, { title = "omp.nvim" })
    end
  end, opts)
  return true
end

return M
