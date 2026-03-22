local M = {}

local config = require("nvim-tree-crossclip.config")

local ttl_timer = nil

local function get_path()
	return config.get().clipboard_path
end

function M.read()
	local cfg = config.get()
	local path = cfg.clipboard_path
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
	local ttl = cfg.ttl or 0
	if ttl > 0 and decoded.ts and (os.time() - decoded.ts) > ttl then
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

M.on_expire = nil

local function schedule_ttl_timer()
	if ttl_timer then
		ttl_timer:stop()
		ttl_timer:close()
		ttl_timer = nil
	end
	local ttl = config.get().ttl or 0
	if ttl <= 0 then
		return
	end
	ttl_timer = vim.uv.new_timer()
	ttl_timer:start(ttl * 1000, 0, vim.schedule_wrap(function()
		ttl_timer:close()
		ttl_timer = nil
		local clip = M.read()
		if clip then
			return
		end
		if vim.fn.filereadable(get_path()) == 1 then
			M.write({ copy = {}, cut = {} })
		end
		if M.on_expire then
			M.on_expire()
		end
	end))
end

function M.write(payload, opts)
	local options = opts or {}
	payload = vim.tbl_extend("force", payload, { ts = os.time() })
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
	local has_items = (payload.copy and #payload.copy > 0) or (payload.cut and #payload.cut > 0)
	if has_items then
		schedule_ttl_timer()
	end
end

function M.path()
	return get_path()
end

return M
