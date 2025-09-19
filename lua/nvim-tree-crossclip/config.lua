local M = {}

M._opts = {
	persistent_clipboard = true,
	-- default set in setup using stdpath('state')
	clipboard_path = nil,
}

function M.setup(opts)
	M._opts = vim.tbl_deep_extend("force", M._opts, opts or {})
	if not M._opts.clipboard_path then
		local state_dir = vim.fn.stdpath("state")
		M._opts.clipboard_path = state_dir .. "/nvim_tree_crossclip_clipboard.json"
	end
	return M._opts
end

function M.get()
	return M._opts
end

return M
