-- Automatically run :PackerCompile whenever plugins.lua is updated with an autocommand:
vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('PACKER', { clear = true }),
    pattern = 'plugins.lua',
    command = 'source <afile> | PackerCompile',
})

return require('packer').startup(function(use)
    -- Packer can manage itself
    use {
        'wbthomason/packer.nvim',
        commit = 'ea0cc3c',
    }

    -- Devicons
    -- Required by nvim-tree, lualine, and bufferline
    use {
        'nvim-tree/nvim-web-devicons',
        tag = 'nerd-v2-compat',
    }

    -- Nvim file tree
    use {
        'nvim-tree/nvim-tree.lua',
        commit = '5e4475d',
        config = function()
            require("config.plugins.nvim-tree")
        end
    }

    -- Markdown preview
    use({
        "iamcco/markdown-preview.nvim",
        commit = 'a923f5f',
        run = function() vim.fn["mkdp#util#install"]() end,
    })

    -- Syntax highlighting
    use {
        'nvim-treesitter/nvim-treesitter',
        tag = 'v0.9.1',
        run = function()
            local ts_update = require('nvim-treesitter.install').update({ with_sync = true })
            ts_update()
        end,
        config = function()
            require("config.plugins.nvim-treesitter")
        end
    }

    -- Fuzzyfinder
    use {
        'nvim-telescope/telescope.nvim',
        tag = '0.1.1',
        requires = { { 'nvim-lua/plenary.nvim' } },
        config = function()
            require("config.plugins.telescope")
        end
    }

    -- Git
    use {
        'tpope/vim-fugitive',
        commit = '46eaf89',
    }

    -- LSP
    use {
        'VonHeikemen/lsp-zero.nvim',
        branch = 'v3.x',
        requires = {
            -- LSP Support
            { 'neovim/nvim-lspconfig' }, -- Required
            {
                -- Optional
                'williamboman/mason.nvim',
                run = function()
                    pcall(vim.cmd, 'MasonUpdate')
                end,
            },
            { 'williamboman/mason-lspconfig.nvim' }, -- Optional

            -- Autocompletion
            { 'hrsh7th/nvim-cmp' },     -- Required
            { 'hrsh7th/cmp-nvim-lsp' }, -- Required
            { 'L3MON4D3/LuaSnip' },     -- Required
        },
        config = function()
            require("config.plugins.lsp")
        end
    }

    -- Github Copilot
    use {
        'github/copilot.vim',
        tag = 'v1.12.1',
    }

    -- Gruvbox
    use {
        "ellisonleao/gruvbox.nvim",
        tag = '2.0.0',
        config = function()
            require("config.plugins.colors")
        end
    }

    -- GitGutter
    use {
        'airblade/vim-gitgutter',
        commit = 'fe0e8a2',
        config = function()
            require("config.plugins.gitgutter")
        end
    }

    -- Lualine
    use {
        'nvim-lualine/lualine.nvim',
        commit = '2248ef2',
        config = function()
            require("config.plugins.lualine")
        end
    }

    -- Vertical indent lines
    use {
        "lukas-reineke/indent-blankline.nvim",
        tag = 'v3.3.7',
    }

    -- bufferline
    use {
        'akinsho/bufferline.nvim',
        tag = "v4.4.0",
        config = function ()
            require("config.plugins.bufferline")
        end
    }
end)
