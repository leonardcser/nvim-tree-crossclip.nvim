local M = {}

function M.join_path(dir, name)
	if dir:sub(-1) == "/" then
		return dir .. name
	end
	return dir .. "/" .. name
end

function M.exec_cmd(args)
	if vim.system then
		local result = vim.system(args, { text = true }):wait()
		return result.code == 0, result.stdout, result.stderr
	else
		local cmd = table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
		local out = vim.fn.system(cmd)
		return vim.v.shell_error == 0, out, out
	end
end

return M
