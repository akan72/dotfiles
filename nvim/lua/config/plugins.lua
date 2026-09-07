-- Leader must be set before lazy.nvim loads so that lazy `keys` specs below
-- bind against the intended leader (also set in remaps.lua).
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Bootstrap lazy.nvim (pinned to a stable tag; it self-installs on first launch,
-- so no separate clone step is needed in assimilate.sh).
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local out = vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "--branch=v11.17.5",
        "https://github.com/folke/lazy.nvim.git",
        lazypath,
    })
    if vim.v.shell_error ~= 0 then
        error("Error cloning lazy.nvim:\n" .. out)
    end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    -- Devicons — required by nvim-tree, lualine, and bufferline
    {
        'nvim-tree/nvim-web-devicons',
        tag = 'nerd-v3.2-compat',
    },

    -- Nvim file tree
    {
        'nvim-tree/nvim-tree.lua',
        commit = '5e4475d',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        config = function()
            require("config.plugins.nvim-tree")
        end,
    },

    -- Markdown preview (load only for markdown files)
    {
        "iamcco/markdown-preview.nvim",
        commit = 'a923f5f',
        ft = "markdown",
        build = function() vim.fn["mkdp#util#install"]() end,
    },

    -- Syntax highlighting
    {
        'nvim-treesitter/nvim-treesitter',
        tag = 'v0.10.0',
        build = function()
            local ts_update = require('nvim-treesitter.install').update({ with_sync = true })
            ts_update()
        end,
        config = function()
            require("config.plugins.nvim-treesitter")
        end,
    },

    -- Fuzzyfinder (load on its keys / :Telescope)
    {
        'nvim-telescope/telescope.nvim',
        tag = '0.1.1',
        dependencies = { 'nvim-lua/plenary.nvim' },
        cmd = 'Telescope',
        keys = { '<C-p>', '<leader>pf', '<leader>ps', '<leader>vh' },
        config = function()
            require("config.plugins.telescope")
        end,
    },

    -- Git (load on :Git / <leader>gs)
    {
        'tpope/vim-fugitive',
        commit = '46eaf89',
        cmd = { 'Git', 'G' },
        keys = { { '<leader>gs', '<cmd>Git<cr>', desc = 'Git status' } },
        config = function()
            require("config.plugins.fugitive")
        end,
    },

    -- LSP
    {
        'VonHeikemen/lsp-zero.nvim',
        branch = 'v3.x',
        dependencies = {
            -- LSP Support
            { 'neovim/nvim-lspconfig' }, -- Required
            {
                -- Optional
                'williamboman/mason.nvim',
                build = function()
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
        end,
    },

    -- Gruvbox (colorscheme — load first, before other UI plugins)
    {
        "ellisonleao/gruvbox.nvim",
        tag = '2.0.0',
        priority = 1000,
        lazy = false,
        config = function()
            require("config.plugins.colors")
        end,
    },

    -- GitGutter
    {
        'airblade/vim-gitgutter',
        commit = 'fe0e8a2',
        config = function()
            require("config.plugins.gitgutter")
        end,
    },

    -- Lualine
    {
        'nvim-lualine/lualine.nvim',
        commit = '2248ef2',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        config = function()
            require("config.plugins.lualine")
        end,
    },

    -- Vertical indent lines
    {
        "lukas-reineke/indent-blankline.nvim",
        tag = 'v3.3.7',
    },

    -- bufferline
    {
        'akinsho/bufferline.nvim',
        tag = "v4.9.1",
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        config = function()
            require("config.plugins.bufferline")
        end,
    },

    -- Comments
    {
        'numToStr/Comment.nvim',
        config = function()
            require('Comment').setup()
        end,
    },
})
