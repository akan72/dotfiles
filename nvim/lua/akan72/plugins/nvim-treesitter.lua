require("nvim-treesitter").setup {
	ensure_installed = {
		"lua",
		"python",
		"rust",
		"sql",
		"vim",
	},
	highlight = {
		enable = true
	},
}
