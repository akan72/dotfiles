local g = vim.g
local o = vim.o

-- disable netrw for nvim-tree
g.loaded_netrw = 1
g.loaded_netrwPlugin = 1

-- Map <leader> to space
g.mapleader = " "

-- set termguicolors to enable highlight groups
o.termguicolors = true

o.relativenumber = true
o.tabstop = 4
o.softtabstop = 4
o.shiftwidth = 4

o.encoding = 'utf-8'
