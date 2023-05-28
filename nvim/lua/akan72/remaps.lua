local function map(mode, key, val)
	vim.keymap.set(mode, key, val, { silent = true })
end
