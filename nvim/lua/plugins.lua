packer = require 'packer'
packer.init{}

local use = packer.use
packer.reset()

packer.startup(function()
    use 'wbthomason/packer.nvim' -- Package manager
    use 'neovim/nvim-lspconfig' -- Configurations for Nvim LSP
    use {
      'kyazdani42/nvim-tree.lua',
      requires = {
        'kyazdani42/nvim-web-devicons', -- optional, for file icons
      },
      tag = 'nightly' -- optional, updated every week. (see issue #1193)
    }
    use({
        "iamcco/markdown-preview.nvim",
        run = function() vim.fn["mkdp#util#install"]() end,
    })
  end
)

require'lspconfig'.pyright.setup{}
require("nvim-tree").setup({
  sort_by = "case_sensitive",
  view = {
    adaptive_size = true,
    mappings = {
      list = {
        { key = "u", action = "dir_up" },
      },
    },
  },
  renderer = {
    group_empty = true,
  },
  filters = {
    dotfiles = true,
  },
})
