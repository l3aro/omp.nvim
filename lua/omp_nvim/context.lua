---Editor context snapshot and @placeholder resolution for omp prompts.
---Mirrors opencode.nvim's capture: buf/win/cursor/range are snapshotted
---before the prompt UI opens. @this/@buffer resolve to file references
---(path, or path:start-end) instead of inlined content — the agent reads
---the file itself, so inlining would only waste tokens on big files.
---Buffers with unsaved changes are snapshotted to temp files (disk content
---would be stale); unnamed buffers fall back to raw text.
local Context = {}
Context.__index = Context

---@class omp_nvim.Range
---@field from integer[] { line, col } 1-based; col inclusive 1-based
---@field to integer[] { line, col }
---@field kind "char" | "line" | "block"

---Capture the current visual selection (exits visual mode) or nil.
---@param buf integer
---@return omp_nvim.Range?
local function selection(buf)
  local mode = vim.fn.mode()
  local kind = (mode == "V" and "line") or (mode == "v" and "char") or (mode == "\22" and "block")
  if not kind then
    return nil
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), "x", true)
  local from = vim.api.nvim_buf_get_mark(buf, "<")
  local to = vim.api.nvim_buf_get_mark(buf, ">")
  if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
    from, to = to, from
  end
  if kind == "block" and from[2] > to[2] then
    from[2], to[2] = to[2], from[2]
  end
  return {
    from = { from[1], from[2] + 1 }, -- 0-based mark -> 1-based inclusive col
    to = { to[1], to[2] + 1 },
    kind = kind,
  }
end

---Snapshot buffer lines [from, to] (1-based, inclusive) to a temp file.
---Used for buffers with unsaved changes so the agent never reads stale disk
---content. Temp files are left in the os temp dir (same as bridge.lua's
---oversized-prompt fallback).
---@param buf integer
---@param from integer
---@param to integer
---@return string temp path
local function snapshot(buf, from, to)
  local lines = vim.api.nvim_buf_get_lines(buf, from - 1, to, false)
  local file = vim.fn.tempname()
  vim.fn.writefile(lines, file)
  return file
end

---Context reference for buffer lines [from, to] (1-based, inclusive).
---Named, unmodified buffers reference the real file (path:start-end);
---buffers with unsaved changes get a temp-file snapshot; unnamed buffers
---fall back to the raw text.
---@param buf integer
---@param from integer
---@param to integer
---@return string
function Context.range_reference(buf, from, to)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return table.concat(vim.api.nvim_buf_get_lines(buf, from - 1, to, false), "\n")
  end
  local file = vim.fn.fnamemodify(name, ":~:.")
  if not vim.bo[buf].modified then
    return string.format("@%s:%d-%d", file, from, to)
  end
  return string.format(
    "@%s:%d-%d (unsaved buffer — exact content at %s)",
    file,
    from,
    to,
    snapshot(buf, from, to)
  )
end

---Context reference for a whole buffer, or nil when it has no file name.
---@param buf integer
---@return string?
function Context.buffer_reference(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  local file = vim.fn.fnamemodify(name, ":~:.")
  if not vim.bo[buf].modified then
    return "@" .. file
  end
  return string.format(
    "@%s (unsaved buffer — exact content at %s)",
    file,
    snapshot(buf, 1, vim.api.nvim_buf_line_count(buf))
  )
end

---Snapshot the current editor state. Call while still in visual mode to
---capture a char/block selection; otherwise the cursor position is kept.
---@return omp_nvim.Context
function Context.new()
  local self = setmetatable({}, Context)
  self.win = vim.api.nvim_get_current_win()
  self.buf = vim.api.nvim_win_get_buf(self.win)
  self.cursor = vim.api.nvim_win_get_cursor(self.win)
  self.range = selection(self.buf)
  return self
end

---Path of the snapshot buffer relative to cwd, or nil if unnamed.
---@return string?
function Context:file()
  local name = vim.api.nvim_buf_get_name(self.buf)
  if name == "" then
    return nil
  end
  return vim.fn.fnamemodify(name, ":~:.")
end

---@return string? reference to the visual range, or the whole buffer
function Context:this()
  local file = self:file()
  if not file then
    return nil
  end
  if self.range then
    return Context.range_reference(self.buf, self.range.from[1], self.range.to[1])
  end
  return self:buffer()
end

---@return string? reference to the whole buffer
function Context:buffer()
  return Context.buffer_reference(self.buf)
end

---Resolve @this/@buffer placeholders in a prompt. Unresolvable placeholders
---(e.g. unnamed buffer) stay as written.
---@param prompt string
---@return string
function Context:render(prompt)
  prompt = prompt:gsub("@this", function()
    return self:this() or "@this"
  end)
  prompt = prompt:gsub("@buffer", function()
    return self:buffer() or "@buffer"
  end)
  return prompt
end

return Context
