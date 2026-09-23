# nvim-snapshot

Write a running Neovim's session on demand, from outside Neovim.

A tool that snapshots your terminal (tabs, splits, what runs in each pane) can
restart `nvim .` in the right directory, but not what that nvim had open. This
plugin lets such a tool ask each running Neovim, over its RPC socket, to write a
session file. `nvim -S <file>` then reopens the buffers, splits and tabs.

It is built to be called unattended, at any moment: it never closes a window,
moves the cursor or changes an option for longer than the save itself.

## What it adds over plain `:mksession`

- A fixed `sessionoptions` for the save, restored right after: terminal buffers
  and global options are left out, so the session does not fight your config.
- [oil.nvim](https://github.com/stevearc/oil.nvim) windows survive.
  `:mksession` drops windows showing an oil buffer, which shifts every later
  window. nvim-snapshot keeps their slots and writes a `<session>x.vim` next to
  the session file (Neovim sources it automatically when the session loads) that
  reopens each oil directory in its window.
- A report of what a session cannot keep, for the caller to warn about: buffers
  with unsaved changes, and open files under `/tmp`.
- Session files are written owner-only (mode 600): they list every open path.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "benjaminpeeters/nvim-snapshot", lazy = true }
```

No `setup()` is needed. lazy.nvim loads the plugin on the first
`require("nvim_snapshot")`, so it costs nothing at startup.

## Usage

Every Neovim listens on an RPC socket (`:echo v:servername`, by default
`$XDG_RUNTIME_DIR/nvim.<pid>.0`). From a script:

```sh
nvim --clean --headless --server "$SOCKET" --remote-expr \
  'luaeval("require(\"nvim_snapshot\").save(_A)", "/abs/path/session.vim")'
```

It prints a JSON object:

```json
{"path": "/abs/path/session.vim", "extra": "/abs/path/sessionx.vim",
 "modified": ["/home/me/notes.md"], "tmp_files": []}
```

`extra` is `null` when no oil window needed one. The path must be absolute and
end in `.vim`; anything else raises an error. Reopen with:

```sh
nvim -S /abs/path/session.vim
```

`--clean` keeps the client from loading your own config. Use a timeout on the
call: a Neovim that is busy, or sitting at a "Press ENTER" prompt, answers only
once it is free again (an `input()` prompt does not block it). A request whose
client gave up is dropped; it does not write the session later.

Inside Neovim, the same call is `:lua print(require("nvim_snapshot").save("/abs/path/s.vim"))`.

## Notes

- Tested on Neovim 0.13 (dev). It uses `vim.uv` and `vim.json`, so it needs 0.10+.
- Floating windows are never part of a session (a `:mksession` rule).
- Unsaved changes are not stored in a session: save your buffers, or keep swap
  files on, if a reboot might come before you do.
- If the session is loaded before `VimEnter` (as `nvim -S` does), start screens
  such as alpha-nvim see the restored buffers and stay hidden.

## License

AGPL-3.0, see [LICENSE](LICENSE).
