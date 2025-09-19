local M = {}

local clipboard = require("nvim-tree-crossclip.clipboard")

local function read_clip()
	local clip = clipboard.read_or_default()
	return clip
end

local function write_clip(clip)
	clipboard.write(clip)
end

local function build_list(clip)
	local items = {}
	for i, p in ipairs(clip.copy or {}) do
		table.insert(items, { kind = "copy", index = i, text = p })
	end
	for i, p in ipairs(clip.cut or {}) do
		table.insert(items, { kind = "cut", index = i, text = p })
	end
	return items
end

function M.show()
	local clip = read_clip()
	local items = build_list(clip)
	if #items == 0 then
		vim.notify("crossclip: clipboard empty")
		return
	end

	local lines = {}
	for _, it in ipairs(items) do
		local prefix = (it.kind == "copy") and "C " or "X "
		table.insert(lines, prefix .. it.text)
	end

	local buf = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "nvim-tree-crossclip"

	local function compute_sizes()
		local maxw = 0
		for _, s in ipairs(lines) do
			if #s > maxw then
				maxw = #s
			end
		end
		local width = math.min(math.max(10, maxw + 8), math.floor(vim.o.columns * 0.9))
		local height = math.min(math.max(3, #lines), math.floor(vim.o.lines * 0.6))
		return width, height
	end
	local width, height = compute_sizes()

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = " NvimTreeCrossClip ",
		title_pos = "center",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 3),
		col = math.floor((vim.o.columns - width) / 2),
	})

	-- CrossClip window styling: opaque content, transparent background, white title
	local function define_highlights()
		pcall(vim.api.nvim_set_hl, 0, "NvimTreeCrossClipWindow", { bg = "NONE" })
		pcall(vim.api.nvim_set_hl, 0, "NvimTreeCrossClipBorder", { bg = "NONE" })
		pcall(vim.api.nvim_set_hl, 0, "NvimTreeCrossClipTitle", { fg = "#FFFFFF", bg = "NONE", bold = true })
	end
	define_highlights()
	pcall(
		vim.api.nvim_set_option_value,
		"winhl",
		"Normal:NvimTreeCrossClipWindow,FloatBorder:NvimTreeCrossClipBorder,FloatTitle:NvimTreeCrossClipTitle",
		{ win = win }
	)
	pcall(vim.api.nvim_set_option_value, "winblend", 0, { win = win })

	vim.wo[win].number = true

	-- apply per-line highlights matching nvim-tree clipboard decorators
	local ns = vim.api.nvim_create_namespace("NvimTreeCrossClipUI")
	local function apply_line_highlights()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		for i, it in ipairs(items) do
			local hl = (it.kind == "copy") and "NvimTreeCopiedHL" or "NvimTreeCutHL"
			-- Highlight prefix letter (col 0..1) and path (col 2..end), leaving the space at col 1 unhighlighted
			pcall(vim.api.nvim_buf_set_extmark, buf, ns, i - 1, 0, { end_col = 1, hl_group = hl })
			local line = lines[i] or ""
			pcall(vim.api.nvim_buf_set_extmark, buf, ns, i - 1, 2, { end_col = #line, hl_group = hl })
		end
	end

	local function refresh()
		clip = read_clip()
		items = build_list(clip)
		lines = {}
		for _, it in ipairs(items) do
			local prefix = (it.kind == "copy") and "C " or "X "
			table.insert(lines, prefix .. it.text)
		end
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		-- adapt window size to longest line + 3
		local new_width, new_height = compute_sizes()
		if new_width ~= width or new_height ~= height then
			width, height = new_width, new_height
			pcall(vim.api.nvim_win_set_config, win, {
				relative = "editor",
				style = "minimal",
				border = "rounded",
				title = " NvimTreeCrossClip ",
				title_pos = "center",
				width = width,
				height = height,
				row = math.floor((vim.o.lines - height) / 3),
				col = math.floor((vim.o.columns - width) / 2),
			})
			-- re-apply highlights and line numbers after reconfig
			pcall(
				vim.api.nvim_set_option_value,
				"winhl",
				"Normal:NvimTreeCrossClipWindow,FloatBorder:NvimTreeCrossClipBorder,FloatTitle:NvimTreeCrossClipTitle",
				{ win = win }
			)
			pcall(vim.api.nvim_set_option_value, "winblend", 0, { win = win })
			vim.wo[win].number = true
		end
		if #lines == 0 then
			pcall(function()
				if win and vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_close(win, true)
				end
			end)
			vim.notify("external clipboard cleared")
			return
		end
		apply_line_highlights()
	end

	local function remove_current()
		local lnum = vim.api.nvim_win_get_cursor(win)[1]
		local meta = items[lnum]
		if not meta then
			return
		end
		local current = read_clip()
		local list = current[meta.kind] or {}
		if meta.index < 1 or meta.index > #list then
			return
		end
		table.remove(list, meta.index)
		current[meta.kind] = list
		write_clip(current)
		-- only clear NvimTree clipboard when both lists are actually empty
		pcall(function()
			local empty = (not current.copy or #current.copy == 0) and (not current.cut or #current.cut == 0)
			if empty then
				require("nvim-tree.api").fs.clear_clipboard()
			end
		end)
		pcall(function()
			require("nvim-tree.api").tree.reload()
		end)
		refresh()
	end

	vim.keymap.set("n", "q", function()
		pcall(function()
			vim.api.nvim_win_close(win, true)
		end)
	end, { buffer = buf, nowait = true, noremap = true, silent = true })
	vim.keymap.set("n", "<Esc>", function()
		pcall(function()
			vim.api.nvim_win_close(win, true)
		end)
	end, { buffer = buf, nowait = true, noremap = true, silent = true })
	vim.keymap.set("n", "dd", remove_current, { buffer = buf, nowait = true, noremap = true, silent = true })

	apply_line_highlights()
end

return M
