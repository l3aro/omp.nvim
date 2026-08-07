# omp.nvim

Neovim plugin that talks to the [omp](https://omp.sh/) agent running in your current directory — without leaving your editor.

## ⭐ Motivation

AI works best at small, focused scopes — as a pair programmer with the human driving. You stay in control, craft the code that matters, and keep your skills sharp. omp.nvim just provides the context and connection to make that pairing seamless.

Rather than introduce yet another interaction model, omp.nvim injects prompts into the omp session you already have running — the same session, same history, same files. You keep your environment, your config, your flow.

## ✨ Features

- Inject prompts into the omp session running in the current directory
- `@this` / `@buffer` placeholders resolved to inlined, fenced editor context
- Send the current line, a visual selection, or any `:range` of the file
- Interactive prompt with Enter-to-submit, Esc-to-discard
- Zero-config bridge extension, auto-installed and auto-discovered by omp
- Files omp changes are reloaded automatically when a turn ends
- Simple, sensible, Vim-y defaults

## 📦 Setup

Requires Neovim 0.10+ (uses `vim.uv` pipe transport).

[vim.pack](https://neovim.io/doc/user/pack/#vim.pack) (recommended)

```lua
vim.pack.add({
  {
    src = "https://github.com/l3aro/omp.nvim",
    version = vim.version.range("*"), -- Latest stable release
  },
})
```

<details>
<summary><a href="https://github.com/folke/lazy.nvim">lazy.nvim</a></summary>

```lua
{
  "l3aro/omp.nvim",
  version = "*", -- Latest stable release
}
```

</details>

> [!TIP]
> Run `:checkhealth omp_nvim` after setup.

## 🚀 Usage

### Ask — `:OmpAsk` / `<leader>oa`

Send a prompt to the omp in this directory.

| Form            | Sends                                                     |
| --------------- | --------------------------------------------------------- |
| `:OmpAsk`       | Interactive input; Enter submits, Esc discards            |
| `:OmpAsk text`  | The prompt as given                                       |
| `:5,20OmpAsk`   | Lines 5–20 of the current file as context                 |
| `:%OmpAsk`      | The whole file as context                                 |
| `:'<,'>OmpAsk`  | The last visual range                                     |
| `<leader>oa` (n)| Interactive ask with `@this`/`@buffer` resolved           |
| `<leader>oa` (x)| Ask about the visual selection                            |

Opt out of the default keymaps with `vim.g.omp_nvim_no_keymaps = true`.

### API

```lua
local omp = require("omp_nvim")

omp.prompt("Review the error handling here")                -- Inject a prompt verbatim
omp.send_range(5, 20, "Review these lines:")                -- Send file lines 5-20
omp.send_selection("x", "Explain this:")                    -- Send the last visual selection
omp.ask()                                                   -- Interactive ask, @this/@buffer resolved
```

### Placeholders

`@this` and `@buffer` are replaced with fenced editor context in any non-range `:OmpAsk` (interactive or not) and in `omp.ask()`:

| Placeholder | Context                                   |
| ----------- | ----------------------------------------- |
| `@this`     | Visual range or selection, else current file |
| `@buffer`   | The whole current buffer                  |

## 🛠 How it works

`setup()` installs the bundled bridge extension to `~/.omp/agent/extensions/omp-nvim-bridge.ts`, where every omp auto-discovers it. The extension opens a per-directory Unix socket (`~/.omp/run/omp-nvim/omp-nvim-<hash>.sock`); the plugin sends JSONL prompt frames over it, and the bridge injects them into the live session via `sendUserMessage`. Reinstall manually at any time with `:OmpNvimInstallExtension`.

> [!IMPORTANT]
> The omp instance must have been started (or restarted) after the extension was installed to pick it up.

## 👀 Events

The bridge streams session status back to the plugin. When a turn ends, modified files are reloaded from disk via `checktime` (buffers with local changes are protected). Status events are also exposed for your own handlers:

```lua
require("omp_nvim.bridge").on_status(function(event)
  -- "ready" | "turn_started" | "turn_ended" | "prompt_accepted"
  if event == "turn_started" then
    vim.notify("omp is working…")
  end
end)
```

## ⚙️ Configuration

omp.nvim ships with sensible defaults — there is nothing to configure for basic use. The only option today:

| Option                       | Effect                                   |
| ---------------------------- | ---------------------------------------- |
| `vim.g.omp_nvim_no_keymaps`  | Disable the default `<leader>oa` keymaps |
