local g = vim.g
local o = vim.o
local autocmd = vim.api.nvim_create_autocmd

-- Syntax highlighting automatically on

-- Enable true color support
o.termguicolors = true

-- No errorbell sounds
o.errorbells = false

-- Define tab as 4 characters and move cursor 4 characters when typing tab
o.tabstop = 4
o.softtabstop = 4

-- Set indentation with >> to 4 characters
o.shiftwidth = 4

-- Set indentation with spaces instead of tabs
o.expandtab = true

-- Set autoindent
o.autoindent = true

-- Prevent text wrapping
o.wrap = false

-- Encode files both shown and written in utf-8
o.encoding = 'utf-8'
o.fileencodings = 'utf-8'

-- Case sensitive search for text containing uppercase characters and insensitive search for lowercase characters
o.ignorecase = true
o.smartcase = true

-- Produce no swapfiles
o.swapfile = false

-- Display absolute line number of current line
o.nu = true

-- Display relative line numbers
o.relativenumber = true

-- Set incremental search
o.incsearch = true

-- Show matching braces and speedup
o.showmatch = true
o.matchtime = 3

-- Enable vertical diff splits
o.diffopt = 'vertical'

-- Set veritcal lines at 80, 125 in Python files according to PEP and Github max file length
o.colorcolumn = 125
autocmd(
    { "BufNewFile", "BufRead" }, {
        pattern = "*.py",
        command = 'setlocal colorcolumn=80,125'
    }
)

-- "filetype plugin indent on" is automatically turned on by Neovim

-- Prevent gray sign column from appearing after toggling FileTree and Gdiffsplit
o.foldcolumn = '0'

-- Yank to clipboard with ctrl-c
o.clipboard = 'unnamed'

-- Disables automatic commenting on newline:
o.formatoptions = 'cro'

-- Set update time to 100ms for gitgutter
o.updatetime = 100

-- Turn on sign column by default
o.signcolumn = 'yes'

-- Keep around buffers
o.hidden = true

-- Set undodir and expand tilde to home directory
o.undodir = vim.fn.expand('~/.vim/undodir')
o.undofile = true

-- Turn on automatic scrolling
o.scrolloff = 8

-- Do not highlight current line
o.cursorline = false
-- vim.api.nvim_set_hl(0, "cursorline", { bold = true, ctermbg = 'black' })

-- Disable netrw for nvim-tree
g.loaded_netrw = 1
g.loaded_netrwPlugin = 1

-- Automatically delete all trailing whitespace on save
autocmd(
    "BufWritePre", {
        pattern = "*",
        command = "%s/\\s\\+$//e"
    }
)

-- Don't automatically add missing EOF
o.fixendofline = false

-- Enable mousemovement for highight
o.mousemoveevent = true
