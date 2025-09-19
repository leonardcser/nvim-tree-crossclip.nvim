local M = {}

local api = require("nvim-tree.api")
local uv = vim.loop or vim.uv
local config = require("nvim-tree-crossclip.config")
local clipboard = require("nvim-tree-crossclip.clipboard")
local util = require("nvim-tree-crossclip.util")
local ui = require("nvim-tree-crossclip.ui")

local clipboard_file = nil

local function notify(msg, level)
	vim.notify("nvim-tree: " .. msg, level or vim.log.levels.INFO)
end

local session_clip = { copy = {}, cut = {} }
local clip_watcher

local function list_has_path(node_list, path)
	if not node_list or #node_list == 0 then
		return false
	end
	for _, n in ipairs(node_list) do
		if n and n.absolute_path == path then
			return true
		end
	end
	return false
end

local function restore_decorations()
	local core_ok, core = pcall(require, "nvim-tree.core")
	if not core_ok then
		return
	end
	local explorer = core.get_explorer()
	if not explorer then
		return
	end
	local clip = clipboard.read_or_default()
	if (not clip.copy or #clip.copy == 0) and (not clip.cut or #clip.cut == 0) then
		return
	end
	local copy_set, cut_set = {}, {}
	for _, p in ipairs(clip.copy or {}) do
		copy_set[p] = true
	end
	for _, p in ipairs(clip.cut or {}) do
		cut_set[p] = true
	end

	local to_add_copy, to_add_cut = {}, {}

	local function visit(node)
		if not node then
			return
		end
		local path = node.absolute_path
		if path then
			if copy_set[path] and not list_has_path(explorer.clipboard.data.copy, path) then
				table.insert(to_add_copy, node)
			end
			if cut_set[path] and not list_has_path(explorer.clipboard.data.cut, path) then
				table.insert(to_add_cut, node)
			end
		end
		if node.group_next then
			visit(node.group_next)
		end
		if node.nodes then
			for _, child in ipairs(node.nodes) do
				visit(child)
			end
		end
	end

	visit(explorer)

	local changed = false
	for _, n in ipairs(to_add_copy) do
		changed = true
		table.insert(explorer.clipboard.data.copy, n)
	end
	for _, n in ipairs(to_add_cut) do
		changed = true
		table.insert(explorer.clipboard.data.cut, n)
	end
	if changed then
		explorer.renderer:draw()
	end
end

local function toggle_in_list(list, value)
	for i, v in ipairs(list) do
		if v == value then
			table.remove(list, i)
			return false
		end
	end
	table.insert(list, value)
	return true
end

function M.copy_toggle()
	local node = api.tree.get_node_under_cursor()
	if not node or not node.absolute_path then
		notify("nothing to copy", vim.log.levels.WARN)
		return
	end
	require("nvim-tree.api").fs.copy.node(node)
	local clip = clipboard.read_or_default()
	for i = #clip.cut, 1, -1 do
		if clip.cut[i] == node.absolute_path then
			table.remove(clip.cut, i)
		end
	end
	local added = toggle_in_list(clip.copy, node.absolute_path)
	if not added then
		for i = #session_clip.copy, 1, -1 do
			if session_clip.copy[i] == node.absolute_path then
				table.remove(session_clip.copy, i)
			end
		end
	else
		toggle_in_list(session_clip.copy, node.absolute_path)
	end
	clipboard.write(clip, { notify_on_error = true })
	notify((added and "added " or "removed ") .. node.name .. " to copy set")
end

function M.cut_toggle()
	local node = api.tree.get_node_under_cursor()
	if not node or not node.absolute_path then
		notify("nothing to cut", vim.log.levels.WARN)
		return
	end
	require("nvim-tree.api").fs.cut(node)
	local clip = clipboard.read_or_default()
	for i = #clip.copy, 1, -1 do
		if clip.copy[i] == node.absolute_path then
			table.remove(clip.copy, i)
		end
	end
	local added = toggle_in_list(clip.cut, node.absolute_path)
	if not added then
		for i = #session_clip.cut, 1, -1 do
			if session_clip.cut[i] == node.absolute_path then
				table.remove(session_clip.cut, i)
			end
		end
	else
		toggle_in_list(session_clip.cut, node.absolute_path)
	end
	clipboard.write(clip, { notify_on_error = true })
	notify((added and "added " or "removed ") .. node.name .. " to cut set")
end

function M.show_state()
	ui.show()
end

function M.clear()
	local cleared = { copy = {}, cut = {} }
	clipboard.write(cleared, { notify_on_error = true })
	pcall(function()
		require("nvim-tree.api").fs.clear_clipboard()
	end)
	session_clip.copy, session_clip.cut = {}, {}
	notify("external clipboard cleared")
end

function M.paste()
	local clip = clipboard.read()
	if not clip then
		notify("external clipboard empty", vim.log.levels.WARN)
		return
	end
	local items, mode
	if clip.cut and #clip.cut > 0 then
		items, mode = clip.cut, "cut"
	elseif clip.copy and #clip.copy > 0 then
		items, mode = clip.copy, "copy"
	else
		notify("external clipboard empty", vim.log.levels.WARN)
		return
	end
	local node = api.tree.get_node_under_cursor()
	if not node then
		notify("no destination selected", vim.log.levels.WARN)
		return
	end
	local dest_dir
	if node.type == "directory" then
		dest_dir = node.absolute_path
	else
		dest_dir = vim.fn.fnamemodify(node.absolute_path, ":h")
	end
	local errors = {}
	for _, src in ipairs(items) do
		local base = vim.fn.fnamemodify(src, ":t")
		local target = util.join_path(dest_dir, base)
		local ok, _, err
		if mode == "cut" then
			ok, _, err = util.exec_cmd({ "mv", src, target })
		else
			ok, _, err = util.exec_cmd({ "cp", "-R", "-n", src, target })
		end
		if not ok then
			local cleaned = (err or ""):gsub("\n$", "")
			table.insert(errors, cleaned)
		end
	end
	local new_clip = clipboard.read_or_default()
	new_clip[mode] = {}
	clipboard.write(new_clip, { notify_on_error = true })
	if #errors > 0 then
		notify("paste completed with errors: " .. errors[1], vim.log.levels.ERROR)
	else
		notify("pasted " .. tostring(#items) .. " item(s)")
	end
	api.tree.reload()
end

local function start_clipboard_watcher()
	if not uv or type(uv["new_fs_event"]) ~= "function" or clip_watcher then
		return
	end
	clip_watcher = uv["new_fs_event"]()
	if not clip_watcher then
		return
	end
	if not clipboard_file or clipboard_file == "" then
		return
	end
	local watch_dir = vim.fn.fnamemodify(clipboard_file, ":h")
	local watch_name = vim.fn.fnamemodify(clipboard_file, ":t")
	clip_watcher:start(watch_dir, {}, function(err, filename, _)
		if err then
			return
		end
		if filename ~= watch_name then
			return
		end
		vim.schedule(function()
			local c = clipboard.read_or_default()
			if #c.copy == 0 and #c.cut == 0 then
				pcall(function()
					require("nvim-tree.api").fs.clear_clipboard()
				end)
				session_clip.copy, session_clip.cut = {}, {}
			end
		end)
	end)
end

function M.setup(opts)
	config.setup(opts)
	clipboard_file = config.get().clipboard_path
	start_clipboard_watcher()
	if config.get().persistent_clipboard then
		-- restore clipboard-based decorations whenever the tree renders
		pcall(function()
			api.events.subscribe(api.events.Event.TreeRendered, function()
				vim.schedule(restore_decorations)
			end)
		end)
	end
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			if not config.get().persistent_clipboard then
				local clip = clipboard.read_or_default()
				local function subtract(from_list, remove_list)
					if not from_list or #from_list == 0 then
						return {}
					end
					local remove_set = {}
					for _, p in ipairs(remove_list or {}) do
						remove_set[p] = true
					end
					local out = {}
					for _, p in ipairs(from_list) do
						if not remove_set[p] then
							table.insert(out, p)
						end
					end
					return out
				end
				clip.copy = subtract(clip.copy, session_clip.copy)
				clip.cut = subtract(clip.cut, session_clip.cut)
				clipboard.write(clip, { notify_on_error = true })
			end
			if clip_watcher and clip_watcher.stop then
				pcall(function()
					clip_watcher:stop()
				end)
			end
		end,
	})

	-- user commands
	pcall(vim.api.nvim_del_user_command, "NvimTreeCrossClipShow")
	pcall(vim.api.nvim_del_user_command, "NvimTreeCrossClip")
	pcall(vim.api.nvim_del_user_command, "NvimTreeCrossClipClear")
	vim.api.nvim_create_user_command("NvimTreeCrossClip", function()
		M.show_state()
	end, {})
	vim.api.nvim_create_user_command("NvimTreeCrossClipClear", function()
		M.clear()
	end, {})
end

return M
