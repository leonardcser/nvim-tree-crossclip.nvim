local M = {}

local config = require("nvim-tree-crossclip.config")

local function get_path()
	return config.get().clipboard_path
end

function M.read()
	local path = get_path()
	if not path or path == "" then
		return nil
	end
	if vim.fn.filereadable(path) == 0 then
		return nil
	end
	local ok, decoded = pcall(function()
		local lines = vim.fn.readfile(path)
		return vim.json.decode(table.concat(lines, "\n"))
	end)
	if not ok then
		return nil
	end
	return decoded
end

function M.read_or_default()
	local clip = M.read()
	if not clip or type(clip) ~= "table" then
		clip = { copy = {}, cut = {} }
	else
		clip.copy = clip.copy or {}
		clip.cut = clip.cut or {}
	end
	return clip
end

function M.write(payload, opts)
	local options = opts or {}
	payload.ts = os.time()
	local ok, encoded = pcall(vim.json.encode, payload)
	if not ok then
		if options.notify_on_error then
			vim.notify("nvim-tree: failed to encode clipboard payload", vim.log.levels.ERROR)
		end
		return
	end
	local path = get_path()
	if not path or path == "" then
		return
	end
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile({ encoded }, path)
end

function M.path()
	return get_path()
end

return M
