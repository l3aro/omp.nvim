---Editor context snapshot and @placeholder resolution for omp prompts.
---Mirrors opencode.nvim's capture: buf/win/cursor/range are snapshotted
---before the prompt UI opens, and @this/@buffer resolve to inlined fenced
---text (the bridge injects plain text; opencode instead sends locations the
---CLI resolves — not verified for omp).
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

---Literal text of a range, trimmed to columns.
---@param buf integer
---@param range omp_nvim.Range
---@return string
local function range_text(buf, range)
  local lines = vim.api.nvim_buf_get_lines(buf, range.from[1] - 1, range.to[1], false)
  if #lines == 0 then
    return ""
  end
  if range.kind == "block" then
    for i, line in ipairs(lines) do
      lines[i] = line:sub(range.from[2], math.min(range.to[2], #line))
    end
  elseif range.kind == "char" then
    lines[1] = lines[1]:sub(range.from[2])
    lines[#lines] = lines[#lines]:sub(1, range.to[2])
  end
  return table.concat(lines, "\n")
end

---@param file string
---@param range omp_nvim.Range
---@return string
local function heading(file, range)
  if range.kind == "line" then
    return string.format("%s:%d-%d", file, range.from[1], range.to[1])
  end
  return string.format("%s:L%d:C%d-L%d:C%d", file, range.from[1], range.from[2], range.to[1], range.to[2])
end

---@param title string
---@param text string
---@return string
local function fence(title, text)
  return title .. "\n```\n" .. text .. "\n```"
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

---@return string? fenced text of the visual range, or the cursor line
function Context:this()
  local file = self:file()
  if not file then
    return nil
  end
  if self.range then
    return fence(heading(file, self.range), range_text(self.buf, self.range))
  end
  local line = vim.api.nvim_buf_get_lines(self.buf, self.cursor[1] - 1, self.cursor[1], false)[1] or ""
  return fence(string.format("%s:%d", file, self.cursor[1]), line)
end

---@return string? fenced whole buffer
function Context:buffer()
  local file = self:file()
  if not file then
    return nil
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(self.buf, 0, -1, false), "\n")
  return fence(file, text)
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
