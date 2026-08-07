# Changelog

## [0.1.0] - 2026-08-08

### Features

- Bridge extension (auto-installed into `~/.omp/agent/extensions/`) that connects nvim to the omp instance running in the current directory over a per-directory Unix socket
- `:OmpAsk` with floating input dialog, line/whole-file/visual ranges, and `@this` / `@buffer` context references
- Hold mode: fill omp's input editor without submitting, press Enter there to run
- Default `<leader>oa` / `<leader>oA` keymaps (opt out with `vim.g.omp_nvim_no_keymaps`)
- Files omp changes are reloaded automatically when a turn ends (`checktime`)
- `:checkhealth omp_nvim`

### Bug Fixes

- `@this` without a selection sends the whole buffer instead of nothing
