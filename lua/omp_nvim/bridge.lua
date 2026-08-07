---Socket transport for the omp bridge extension.
---Mirrors the extension's per-cwd socket: ~/.omp/run/omp-nvim/omp-nvim-<sha256(cwd)16>.sock
local M = {}

local DIR = vim.fn.expand("~") .. "/.omp/run/omp-nvim"
local HASH_LEN = 16
local MAX_INLINE_BYTES = 900000

---@return string socket path for the given cwd
function M.socket_path(cwd)
  local hash = vim.fn.sha256(cwd):sub(1, HASH_LEN)
  return DIR .. "/omp-nvim-" .. hash .. ".sock"
end

local conn ---@type { pipe: uv.uv_pipe_t, buf: string, connected: boolean, cwd: string }?
local queue = {} ---@type string[] frames waiting for the connection

local status_handlers = {} ---@type table<fun(event: string), true>

---Register a status-event handler ("ready"|"turn_started"|"turn_ended"|"prompt_accepted").
---@param cb fun(event: string)
function M.on_status(cb)
  status_handlers[cb] = true
end

local function dispatch(event)
  for cb in pairs(status_handlers) do
    pcall(cb, event)
  end
end

local function parse_frame(frame)
  return type(frame) == "table" and frame.type == "status" and frame.event or nil
end

local function on_data(_, data)
  if not data then
    if conn then
      pcall(conn.pipe.close, conn.pipe)
    end
    conn = nil
    return
  end
  conn.buf = conn.buf .. data
  while true do
    local nl = conn.buf:find("\n", 1, true)
    if not nl then
      break
    end
    local line = conn.buf:sub(1, nl - 1)
    conn.buf = conn.buf:sub(nl + 1)
    local ok, frame = pcall(vim.json.decode, line)
    if ok then
      local event = parse_frame(frame)
      if event then
        vim.schedule(function()
          dispatch(event)
        end)
      end
    end
  end
end

local function flush(pipe)
  for _, line in ipairs(queue) do
    pipe:write(line)
  end
  queue = {}
end

---Ensure a connected pipe for the current cwd; initiates an async connect
---when needed. Returns the pipe handle (maybe not yet connected) or nil when
---no bridge socket exists at all.
---@return uv.uv_pipe_t? pipe
local function connect()
  local cwd = vim.fn.getcwd()
  if conn and not conn.pipe:is_closing() then
    if conn.cwd == cwd then
      return conn.pipe
    end
    pcall(conn.pipe.close, conn.pipe)
    conn = nil
    queue = {}
  end
  local path = M.socket_path(cwd)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "socket" then
    return nil
  end
  local pipe = vim.uv.new_pipe(false)
  conn = { pipe = pipe, buf = "", connected = false, cwd = cwd }
  pipe:connect(path, function(err)
    if err then
      pcall(pipe.close, pipe)
      conn = nil
      return
    end
    conn.connected = true
    pipe:read_start(on_data)
    flush(pipe)
  end)
  return pipe
end

---Send one JSONL frame to the bridge.
---@param frame table
---@return boolean ok
---@return string? err
function M.send(frame)
  local pipe = connect()
  if not pipe then
    return false, "no omp bridge in " .. vim.fn.getcwd() .. " (is omp running there?)"
  end
  local line = vim.json.encode(frame) .. "\n"
  if conn.connected then
    return pipe:write(line) ~= nil
  end
  queue[#queue + 1] = line
  return true
end

---Inject a prompt into the running omp session.
---@param text string
---@return boolean ok
---@return string? err
function M.prompt(text)
  if #text > MAX_INLINE_BYTES then
    local file = vim.fn.tempname() .. ".md"
    vim.fn.writefile(vim.split(text, "\n", { plain = true }), file)
    text = "Context is in " .. file
  end
  return M.send({ type = "prompt", text = text })
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    if conn then
      pcall(conn.pipe.close, conn.pipe)
    end
    conn = nil
  end,
})

return M
