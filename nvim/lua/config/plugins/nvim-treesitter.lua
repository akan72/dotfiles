require("nvim-treesitter").setup {
	ensure_installed = {
		"help",
		"lua",
		"javascript",
		"python",
		"rust",
		"sql",
		"typescript",
		"vim",
	},
	highlight = {
		enable = true
	},
	-- Install parsers synchronously (only applied to `ensure_installed`)
	sync_install = false,
	-- Automatically install missing parsers when entering buffer
	auto_install = true,
}
