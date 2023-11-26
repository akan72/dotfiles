-- Map <leader> to space
vim.g.mapleader = " "
vim.g.localleader = " "

local function map(mode, key, val)
    vim.keymap.set(mode, key, val, { noremap = true, silent = true })
end

-- Indent with Tab
map("n", "<Tab>", ">>")

-- Dedent with Shift + Tab
map("n", "<S-Tab>", "<<")

-- Clear highlighting by presssing <leader><leader>
map("n", "<leader><leader>", ":noh<cr>")

-- Append blank lines with Enter. Prevent comments from continuing
map("n", "<Enter>", "o<ESC>S<ESC>")

-- Prepend blank lines with Shift + Enter. Prevent comments from continuing
map("n", "<S-Enter>", "O<ESC>S<ESC>")

-- Navigate between panes with vim movement keys
map("n", "<leader>h", ":wincmd h<CR>")
map("n", "<leader>j", ":wincmd j<CR>")
map("n", "<leader>k", ":wincmd k<CR>")
map("n", "<leader>l", ":wincmd l<CR>")

-- Center cursor when doing half-page jumps
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")

-- Search helpdocs for word under cursor
map("n", "<leader>gh", ":h <C-R>=expand('<cword>')<CR><CR>")

-- Center current search result to middle of screen
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Move highlighted groups in visual mode (with indents)
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")

-- Preserve copied text after paste
map("x", "<leader>p", "\"dP")

-- Make Q a noop
map("n", "Q", "<nop>")
