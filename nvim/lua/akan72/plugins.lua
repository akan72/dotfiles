-- Automatically run :PackerCompile whenever plugins.lua is updated with an autocommand:
vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('PACKER', { clear = true }),
	pattern = 'plugins.lua',
    command = 'source <afile> | PackerCompile',
})

return require('packer').startup(function(use)
	-- Packer can manage itself
	use 'wbthomason/packer.nvim'

	-- Nvim file tree
	use {
		'nvim-tree/nvim-tree.lua',
		requires = {
			'nvim-tree/nvim-web-devicons', -- optional, for file icons
		},
		config = function()
			require("akan72.plugins.nvim-tree")
		end
	}

	-- Markdown preview
	use({
		"iamcco/markdown-preview.nvim",
		run = function() vim.fn["mkdp#util#install"]() end,
	})

	-- Vertical indent lines
	use {
		"lukas-reineke/indent-blankline.nvim",
		config = function()
			require("akan72.plugins.indent_blankline")
		end
	}

	-- LSP
	use {
		'nvim-treesitter/nvim-treesitter',
		run = function()
			local ts_update = require('nvim-treesitter.install').update({ with_sync = true })
			ts_update()
		end,
		config = function()
			require("akan72.plugins.nvim-treesitter")
		end
	}

	-- Fuzzyfinder
	use {
		'nvim-telescope/telescope.nvim', tag = '0.1.1',
		requires = { {'nvim-lua/plenary.nvim'} }
	}
end)
