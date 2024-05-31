vim.keymap.set("n", "<leader>gs", vim.cmd.Git);
-- TODO: config
-- Create autocmd to go back to main pane when closing diff window

-- " Close fugitive status with q (TODO: Add wincmd l here)
-- autocmd FileType fugitive nnoremap <buffer>q :q<CR>
--
-- " Open a vertical diffsplit, close NERDTree and remove gray foldcolumn bar
-- nmap <leader>gd :NERDTreeClose<CR>:Gdiffsplit<CR>:set foldcolumn=0<CR>:wincmd l<CR>
--
-- " Close diff buffer and switch to working directory version of a file.
-- " Return back to original state with NERDTree open but with cursor in main pane.
-- nnoremap <Leader>gD :diffoff!<CR><C-W>h:bd<CR>:NERDTreeToggle<CR>:wincmd l<CR>
--
-- " Choose LHS file when resolving a merge conflict
-- nmap <leader>gf :diffget //3<CR>
--
-- " Choose RHS file when resolving a merge conflict
-- nmap <leader>gh :diffget //2<CR>


--" Git fugitive
--" Create mappings for Git status, commit, push, and diff
--nmap <leader>gc :Gcommit<CR>
--nmap <leader>gp :Gpush<CR>
--nmap <leader>gs :vertical belowright G<CR>
--
--" Close fugitive status with q
--autocmd FileType fugitive nnoremap <buffer>q :q<CR>
--" Open a vertical diffsplit, close NERDTree and remove gray foldcolumn bar
--nmap <leader>gd :NERDTreeClose<CR>:Gdiffsplit<CR>:set foldcolumn=0<CR>:wincmd l<CR>
--
--" Close diff buffer and switch to working directory version of a file.
--" Return back to original state with NERDTree open but with cursor in main pane.
--nnoremap <Leader>gD :diffoff!<CR><C-W>h:bd<CR>:NERDTreeToggle<CR>:wincmd l<CR>

-- TODO: Skip these
--
--" Choose LHS file when resolving a merge conflict
--nmap <leader>gf :diffget //3<CR>
--
--" Choose RHS file when resolving a merge conflict
--nmap <leader>gh :diffget //2<CR>
