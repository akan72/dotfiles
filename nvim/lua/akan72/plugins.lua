-- Only required if you have packer configured as `opt`
vim.cmd [[packadd packer.nvim]]

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
			require("nvim-tree").setup {
				sort_by = "name",
				view = {
					adaptive_size = true,
				}
			}
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
			require("indent-blankline").setup {
			    -- Turn on context by default
				show_current_context = true,
				show_current_context_start = true,
			}
		end
	}

	-- LSP
	use {
		'nvim-treesitter/nvim-treesitter',
		run = function()
		local ts_update = require('nvim-treesitter.install').update({ with_sync = true })
		ts_update()
		end,
	}

	-- Fuzzyfinder
	use {
		'nvim-telescope/telescope.nvim', tag = '0.1.1',
		-- or                            , branch = '0.1.x',
		requires = { {'nvim-lua/plenary.nvim'} }
	}
end)
