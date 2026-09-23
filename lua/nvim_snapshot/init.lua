-- nvim-snapshot: write this Neovim's session on demand, for a tool outside Neovim.
--
-- An external caller (a terminal-layout snapshot, a cron job) reaches a running
-- Neovim over its RPC socket and calls save(); `nvim -S <file>` later reopens the
-- buffers, splits and tabs. The call can come at any moment, unattended, so it
-- must never change what is on screen.

local M = {}

-- Left out on purpose:
--   terminal  a restored terminal buffer would be a new, empty shell
--   options   global options belong to the user's config, not to a stale session
-- "blank" is kept: :mksession drops windows whose buffer it cannot reload, oil's
-- acwrite buffers among them, which would shift every later window. With
-- "blank" they stay in the layout as empty windows and the x.vim below refills
-- them. Floating windows are never saved by :mksession.
local SESSION_OPTIONS = "blank,buffers,curdir,folds,help,tabpages,winsize,localoptions"

-- A session file ends by sourcing "<session>x.vim" when it exists, after the
-- layout is rebuilt, so oil windows are reopened from there.
local function extra_path(path)
    return (path:gsub("%.vim$", "x.vim"))
end

local function oil_windows()
    local found = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
        if vim.api.nvim_win_get_config(win).relative == "" and name:match("^oil://") then
            local tabwin = vim.fn.win_id2tabwin(win)
            table.insert(found, { tab = tabwin[1], win = tabwin[2], url = name })
        end
    end
    return found
end

local function write_extra(path, windows)
    local lines = {
        "\" Written by nvim-snapshot: reopen the oil windows :mksession left blank",
        "let s:snapshot_tab = tabpagenr() | let s:snapshot_win = winnr()",
    }
    for _, w in ipairs(windows) do
        table.insert(lines, string.format(
            "exe '%dtabnext' | exe '%dwincmd w' | exe 'edit ' . fnameescape(%s)",
            w.tab, w.win, vim.fn.string(w.url)))
    end
    table.insert(lines, "exe s:snapshot_tab . 'tabnext' | exe s:snapshot_win . 'wincmd w'")
    vim.fn.writefile(lines, path)
    vim.uv.fs_chmod(path, tonumber("600", 8))
end

-- Writes the session to `path` and returns a JSON string:
--   path       the session file written
--   extra      the x.vim written next to it, or null when no oil window needed one
--   modified   listed buffers with unsaved changes (a session does not keep them)
--   tmp_files  listed buffers under /tmp, which most systems clear at boot
function M.save(path)
    if type(path) ~= "string" or not path:match("^/.*%.vim$") then
        error("nvim_snapshot.save: expected an absolute path ending in .vim, got " .. vim.inspect(path))
    end
    local saved_options = vim.o.sessionoptions
    vim.o.sessionoptions = SESSION_OPTIONS
    local ok, err = pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(path))
    vim.o.sessionoptions = saved_options
    if not ok then
        error("nvim_snapshot.save: mksession failed: " .. tostring(err))
    end
    -- A session file lists the path of everything open: owner-only
    vim.uv.fs_chmod(path, tonumber("600", 8))

    local extra = vim.NIL
    local windows = oil_windows()
    if #windows > 0 then
        extra = extra_path(path)
        write_extra(extra, windows)
    elseif vim.uv.fs_stat(extra_path(path)) then
        -- A stale x.vim from an earlier save to this path would be sourced too
        os.remove(extra_path(path))
    end

    local modified, tmp_files = {}, {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buf)
        if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" and name ~= "" then
            if vim.bo[buf].modified then
                table.insert(modified, name)
            end
            if name:match("^/tmp/") then
                table.insert(tmp_files, name)
            end
        end
    end
    return vim.json.encode({ path = path, extra = extra, modified = modified, tmp_files = tmp_files })
end

return M
