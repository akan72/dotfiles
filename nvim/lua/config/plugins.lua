-- Leader must be set before lazy.nvim loads so that lazy `keys` specs below
-- bind against the intended leader (also set in remaps.lua).
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Verify downloaded code before adding it to the runtime path. No startup downloads.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
require("config.trusted-bootstrap").verify_all()
-- lazy.setup requires loadplugins=true, then disables native loading itself.
-- Keep arbitrary native packages outside packpath during this handoff.
vim.go.packpath = vim.env.VIMRUNTIME
vim.go.loadplugins = true
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    -- Devicons — required by nvim-tree, lualine, and bufferline
    {
        'nvim-tree/nvim-web-devicons',
        commit = '21417212f640a1dad28a1408f04468819848f5e7',
    },

    -- Nvim file tree
    {
        'nvim-tree/nvim-tree.lua',
        commit = '5e4475d8bf7a3646164e01d9b65ef68369b17e3c',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        config = function()
            require("config.plugins.nvim-tree")
        end,
    },

    -- Markdown preview (load only for markdown files)
    {
        "iamcco/markdown-preview.nvim",
        commit = 'a923f5fc5ba36a3b17e289dc35dc17f66d0548ee',
        ft = "markdown",
        enabled = false, -- Release binaries need independently reviewed hashes.
    },

    -- Syntax highlighting
    {
        'nvim-treesitter/nvim-treesitter',
        commit = '42fc28ba918343ebfd5565147a42a26580579482',
        config = function()
            require("config.plugins.nvim-treesitter")
        end,
    },

    -- Fuzzyfinder (load on its keys / :Telescope)
    {
        'nvim-telescope/telescope.nvim',
        commit = 'c1a2af0af69e80e14e6b226d3957a064cd080805',
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
        commit = '46eaf8918b347906789df296143117774e827616',
        cmd = { 'Git', 'G' },
        keys = { { '<leader>gs', '<cmd>Git<cr>', desc = 'Git status' } },
        config = function()
            require("config.plugins.fugitive")
        end,
    },

    -- Server definitions; native Neovim owns LSP, completion and snippets.
    {
        'neovim/nvim-lspconfig',
        commit = 'd224a1920728ba129880efc700d4a0180ac4ecbb',
        lazy = false,
        config = function()
            require("config.plugins.lsp")
        end,
    },

    -- Gruvbox (colorscheme — load first, before other UI plugins)
    {
        "ellisonleao/gruvbox.nvim",
        commit = '61b0b3be2f0cfd521667403a0367298144d6c165',
        priority = 1000,
        lazy = false,
        config = function()
            require("config.plugins.colors")
        end,
    },

    -- GitGutter
    {
        'airblade/vim-gitgutter',
        commit = 'fe0e8a2630eef548e4122096e4e2241f42208fe3',
        config = function()
            require("config.plugins.gitgutter")
        end,
    },

    -- Lualine
    {
        'nvim-lualine/lualine.nvim',
        commit = '2248ef254d0a1488a72041cfb45ca9caada6d994',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        config = function()
            require("config.plugins.lualine")
        end,
    },

    -- Vertical indent lines
    {
        "lukas-reineke/indent-blankline.nvim",
        commit = '29be0919b91fb59eca9e90690d76014233392bef',
    },

    -- bufferline
    {
        'akinsho/bufferline.nvim',
        commit = '655133c3b4c3e5e05ec549b9f8cc2894ac6f51b3',
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
}, {
    local_spec = false,
    install = { missing = false },
    checker = { enabled = false },
    change_detection = { enabled = false },
    rocks = { enabled = false },
    pkg = { enabled = false },
})
