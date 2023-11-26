local function map(mode, key, val)
	vim.keymap.set(mode, key, val, { silent = true })
end

-- Clear highlighting by presssing <leader><leader>
map("n", "<leader><leader>", ":noh<cr>")

-- Append and prepend blank lines with <leader>?<Enter>
map("n", "<Enter>", ":call append(line('.'), '')<CR>")
map("n", "<leader><Enter>", ":call append(line('.')-1, '')<CR>")

-- Navigate between panes with movement keys
map("n", "<leader>h", ":wincmd h<CR>")
map("n", "<leader>j", ":wincmd j<CR>")
map("n", "<leader>k", ":wincmd k<CR>")
map("n", "<leader>l", ":wincmd l<CR>")

-- Move highlighted groups with indents
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")

-- Center cursor when doing half-page jumps
map("n", "<C-d>", "<C-d>zz")
map("n", "<C->", "<C-u>zz")

-- Center current search result to middle of screen
map("n", "n", "nzzzv")
map("n", "N", "nzzzv")

-- Preserve copied text after paste
map("x", "<leader>p", "\"dP")

-- Make Q a noop
map("n", "Q", "<nop>")
