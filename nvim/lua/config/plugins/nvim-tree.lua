local autocmd = vim.api.nvim_create_autocmd
local tree = require('nvim-tree')
local api = require "nvim-tree.api"

tree.setup {
    -- Sort by file name.
    sort_by = "name",
    view = {
        -- Turn on adaptive size
        adaptive_size = true,
        -- Turn on and relative line numbers
        relativenumber = true,
        -- Turn off sign column only within tree
        signcolumn = 'no',
    },
    -- Root folder is displayed by bufferline
    renderer = {
        root_folder_label = false,
    }
}

-- Toggle tree with <leader>t
vim.keymap.set("n", "<leader>t", ":NvimTreeToggle<CR>")

-- Find current file in tree
vim.keymap.set("n", "<leader>r", ":NvimTreeFindFile<CR>")

-- Open tree when entering vim but move cursor to main text buffer
autocmd("VimEnter", {
    callback = function()
        api.tree.open()
        vim.cmd("wincmd l")
    end
})

-- Close and save all buffers when running :q in tree
autocmd("FileType", {
    pattern = "NvimTree",
    callback = function()
        vim.keymap.set("n", ":q", ":wqa")
    end
})

-- TODO:
-- Automatically close tree if it's the last buffer
-- autocmd("BufEnter", {
--     nested = true,
--     callback = function()
--         if #vim.api.nvim_list_wins() == 1 and vim.api.nvim_buf_get_name(0):match("NvimTree_") ~= nil then
--             vim.cmd "quit"
--         end
--     end
-- })

--" Nerdtree
--nnoremap <leader>f :NERDTreeToggle<CR>
--let NERDTreeMinimalUI = 1
--let NERDTreeDirArrows = 1
--" Highlighting full name with same color as devicon
--let g:NERDTreeFileExtensionHighlightFullName = 1
--let g:NERDTreeExactMatchHighlightFullName = 1
--let g:NERDTreePatternMatchHighlightFullName = 1

--" Turn off sign column within Nerdtree
--autocmd filetype nerdtree s
--" Open a vertical diffsplit, close NERDTree and remove gray foldcolumn bar
--nmap <leader>gd :NERDTreeClose<CR>:Gdiffsplit<CR>:set foldcolumn=0<CR>:wincmd l<CR>
--
--" Close diff buffer and switch to working directory version of a file.
--" Return back to original state with NERDTree open but with cursor in main pane.
--nnoremap <Leader>gD :diffoff!<CR><C-W>h:bd<CR>:NERDTreeToggle<CR>:wincmd l<CR>etlocal signcolumn=no
