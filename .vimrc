if !exists('g:syntax_on')
    syntax enable
endif

set noerrorbells
set tabstop=4 softtabstop=4
set shiftwidth=4
set expandtab
set smartindent
set nu
set nowrap
set smartcase
set noswapfile
set relativenumber
set incsearch
set showmatch
set colorcolumn=125
set encoding=utf-8
set fileencodings=utf-8

" Disables automatic commenting on newline:
set formatoptions=cro
" Automatically delete all trailing whitespace on save
autocmd BufWritePre * %s/\s\+$//e

" Vim plug call
call plug#begin('~/.vim/.plugged')

Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'VundleVim/Vundle.vim'
Plug 'flazz/vim-colorschemes'
Plug 'ervandew/supertab'

Plug 'preservim/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'tiagofumo/vim-nerdtree-syntax-highlight'
Plug 'ryanoasis/vim-devicons'
Plug 'tpope/vim-fugitive'
Plug 'vim-airline/vim-airline'

call plug#end()

" Setting colorscheme
colorscheme gruvbox
let g:gruvbox_contrast_dark = 'hard'
set background=dark

" Yank to clipboard with ctrl-c
vmap <C-c> "+y

" Window resizing
let g:netrw_browse_split = 2
let g:netrw_winsize = 25
let g:netrw_banner = 0

" Reassign leader to space
let mapleader = "\<Space>"

" Append and prepend blank lines with <leader>?<Enter>
nnoremap <Enter> :call append(line('.'), '')<CR>
nnoremap <leader><Enter> :call append(line('.')-1, '')<CR>

"  Navigate between windows with movement keys
nnoremap <leader>h :wincmd h<CR>
nnoremap <leader>j :wincmd j<CR>
nnoremap <leader>k :wincmd k<CR>
nnoremap <leader>l :wincmd l<CR>

" Nerdtree
nnoremap <leader>f :NERDTreeToggle<CR>
let NERDTreeMinimalUI = 1
let NERDTreeDirArrows = 1

" Automatically open nerdtree on startup, but move cursor to main window
autocmd VimEnter * NERDTree
autocmd VimEnter * wincmd p

" Automatically close nerdtree if it's the last buffer
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

" Devicons
if exists("g:loaded_webdevicons")
    call webdevicons#refresh()
endif

" Highling full name with same color as devicon
let g:NERDTreeFileExtensionHighlightFullName = 1
let g:NERDTreeExactMatchHighlightFullName = 1
let g:NERDTreePatternMatchHighlightFullName = 1

" CoC
nmap <leader>gd <Plug>(coc-definition)
nmap <leader>gt <Plug>(coc-type-definition)
nmap <leader>gr <Plug>(coc-references)
nmap <leader>rr <Plug>(coc-rename)

" Git fugitive
" Choose LHS file when resolving a merge conflict
nmap <leader>gf :diffget //3<CR>

" Choose RHS file when resolving a merge conflict
nmap <leader>gh :diffget //2<CR>

" Git status, commit, and push
nmap <leader>gs :G<CR>
nmap <leader>gc :Gcommit<CR>
nmap <leader>gp :Gpush<CR>

