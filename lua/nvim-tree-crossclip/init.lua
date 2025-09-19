local M = {}

local api = require("nvim-tree.api")
local uv = vim.loop or vim.uv

local state_dir = vim.fn.stdpath("state")
local clipboard_file = state_dir .. "/nvim_tree_clipboard.json"

local function notify(msg, level)
	vim.notify("nvim-tree: " .. msg, level or vim.log.levels.INFO)
end

local session_clip = { copy = {}, cut = {} }
local clip_watcher

local function read_external_clipboard()
	if vim.fn.filereadable(clipboard_file) == 0 then
		return nil
	end
	local ok, decoded = pcall(function()
		local lines = vim.fn.readfile(clipboard_file)
		return vim.json.decode(table.concat(lines, "\n"))
	end)
	if not ok then
		return nil
	end
	return decoded
end

local function write_external_clipboard_full(payload)
	payload.ts = os.time()
	local ok, encoded = pcall(vim.json.encode, payload)
	if not ok then
		notify("failed to encode clipboard payload", vim.log.levels.ERROR)
		return
	end
	vim.fn.mkdir(state_dir, "p")
	vim.fn.writefile({ encoded }, clipboard_file)
end

local function read_or_default_clipboard()
	local clip = read_external_clipboard()
	if not clip or type(clip) ~= "table" then
		clip = { copy = {}, cut = {} }
	else
		clip.copy = clip.copy or {}
		clip.cut = clip.cut or {}
	end
	return clip
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
	local clip = read_or_default_clipboard()
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
	write_external_clipboard_full(clip)
	notify((added and "added " or "removed ") .. node.name .. " to copy set")
end

function M.cut_toggle()
	local node = api.tree.get_node_under_cursor()
	if not node or not node.absolute_path then
		notify("nothing to cut", vim.log.levels.WARN)
		return
	end
	require("nvim-tree.api").fs.cut(node)
	local clip = read_or_default_clipboard()
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
	write_external_clipboard_full(clip)
	notify((added and "added " or "removed ") .. node.name .. " to cut set")
end

local function join_path(dir, name)
	if dir:sub(-1) == "/" then
		return dir .. name
	end
	return dir .. "/" .. name
end

local function exec_cmd(args)
	if vim.system then
		local result = vim.system(args, { text = true }):wait()
		return result.code == 0, result.stdout, result.stderr
	else
		local cmd = table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
		local out = vim.fn.system(cmd)
		return vim.v.shell_error == 0, out, out
	end
end

function M.paste()
	local clip = read_external_clipboard()
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
		local target = join_path(dest_dir, base)
		local ok, _, err
		if mode == "cut" then
			ok, _, err = exec_cmd({ "mv", src, target })
		else
			ok, _, err = exec_cmd({ "cp", "-R", "-n", src, target })
		end
		if not ok then
			local cleaned = (err or ""):gsub("\n$", "")
			table.insert(errors, cleaned)
		end
	end
	local new_clip = read_or_default_clipboard()
	new_clip[mode] = {}
	write_external_clipboard_full(new_clip)
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
	clip_watcher:start(state_dir, {}, function(err, filename, _)
		if err then
			return
		end
		if filename ~= vim.fn.fnamemodify(clipboard_file, ":t") then
			return
		end
		vim.schedule(function()
			local c = read_or_default_clipboard()
			if #c.copy == 0 and #c.cut == 0 then
				pcall(function()
					require("nvim-tree.api").fs.clear_clipboard()
				end)
				session_clip.copy, session_clip.cut = {}, {}
			end
		end)
	end)
end

function M.setup()
	start_clipboard_watcher()
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			local clip = read_or_default_clipboard()
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
			write_external_clipboard_full(clip)
			if clip_watcher and clip_watcher.stop then
				pcall(function()
					clip_watcher:stop()
				end)
			end
		end,
	})
end

return M
