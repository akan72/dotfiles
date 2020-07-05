" Enable syntax highlighting
if !exists('g:syntax_on')
    syntax enable
endif

" Enable true color support
set termguicolors

" No errorbell sounds
set noerrorbells

" Define tab as 4 characters and move cursor 4 characters when typing tab
set tabstop=4 softtabstop=4

" Set indentation with >> to 4 characters
set shiftwidth=4

" Set indentation with spaces instead of tabs
set expandtab

" Set autoindent
set autoindent

" Prevent text wrapping
set nowrap

" Encode files both shown and written in utf-8
set encoding=utf-8
set fileencodings=utf-8

" Case sensitive search for text containing uppercase characters and insensitive search for lowercase characters
set ignorecase smartcase

" Produce no swapfiles
set noswapfile

" Display line numbers
set nu

" Set relative line numbers
set relativenumber

" Set incremental search
set incsearch

" Show matching braces and speedup
set showmatch
set matchtime=3

" Enable vertical diff splits
set diffopt=vertical

" Add vertical column for Github max file length
set colorcolumn=125

" Automatically set 'filetype' option, add filetype's plugin and indent files to runtime path
filetype plugin indent on

" Prevent gray sign column from appearing after toggling NERDTree and Gdiffsplit
set foldcolumn=0

" Yank to clipboard with ctrl-c
set clipboard=unnamed

" Disables automatic commenting on newline:
set formatoptions-=cro

" Set update time to 100ms for gitgutter
set updatetime=100

" Turn on sign column by default
set signcolumn=yes

" Automatically delete all trailing whitespace on save
autocmd BufWritePre * %s/\s\+$//e

" Vim plug call
call plug#begin('~/.vim/.plugged')

Plug 'VundleVim/Vundle.vim'
Plug 'flazz/vim-colorschemes'

Plug 'ervandew/supertab'
Plug 'neoclide/coc.nvim', {'branch': 'release'}

Plug 'preservim/nerdtree'
Plug 'tpope/vim-fugitive'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'airblade/vim-gitgutter'
Plug 'tiagofumo/vim-nerdtree-syntax-highlight'

Plug 'ryanoasis/vim-devicons'
Plug 'vim-airline/vim-airline'

call plug#end()

" Setting colorscheme
colorscheme gruvbox
let g:gruvbox_contrast_dark = 'hard'
set background=dark

" Window resizing defaults
let g:netrw_browse_split = 2
let g:netrw_winsize = 25
let g:netrw_banner = 0

" Reassign <leader> to space
let mapleader = "\<Space>"

" Clear highlighting by presssing <Leader><space>
nnoremap <leader><leader> :noh<cr>

" Append and prepend blank lines with <leader>?<Enter>
nnoremap <Enter> :call append(line('.'), '')<CR>
nnoremap <leader><Enter> :call append(line('.')-1, '')<CR>

"  Navigate between panes with movement keys
nnoremap <leader>h :wincmd h<CR>
nnoremap <leader>j :wincmd j<CR>
nnoremap <leader>k :wincmd k<CR>
nnoremap <leader>l :wincmd l<CR>

" Enable top-down cycling for SuperTab
let g:SuperTabDefaultCompletionType = "<c-n>"

" Nerdtree
nnoremap <leader>f :NERDTreeToggle<CR>
let NERDTreeMinimalUI = 1
let NERDTreeDirArrows = 1

" Highlighting full name with same color as devicon
let g:NERDTreeFileExtensionHighlightFullName = 1
let g:NERDTreeExactMatchHighlightFullName = 1
let g:NERDTreePatternMatchHighlightFullName = 1

" Automatically open nerdtree on startup, but move cursor to main window
autocmd VimEnter * NERDTree
autocmd VimEnter * wincmd p

" Automatically close nerdtree if it's the last buffer
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

" Close all buffers when running :q in NERDTree
autocmd FileType nerdtree nnoremap <buffer>:q :qa

" Devicons
if exists("g:loaded_webdevicons")
    call webdevicons#refresh()
endif

" CoC mappings
nmap <leader>jd <Plug>(coc-definition)
nmap <leader>jt <Plug>(coc-type-definition)
nmap <leader>jr <Plug>(coc-references)
nmap <leader>rr <Plug>(coc-rename)

" Git fugitive
" Create mappings for Git status, commit, push, and diff
nmap <leader>gc :Gcommit<CR>
nmap <leader>gp :Gpush<CR>
nmap <leader>gs :vertical belowright G<CR>

" Close fugitive status with q
autocmd FileType fugitive nnoremap <buffer>q :q<CR>

" Open a vertical diffsplit, close NERDTree and remove gray foldcolumn bar
nmap <leader>gd :NERDTreeClose<CR>:Gdiffsplit<CR>:set foldcolumn=0<CR>

" Close diff buffer and switch to working directory version of a file
nnoremap <Leader>gD :diffoff!<CR><C-W>h:bd<CR>:NERDTreeToggle<CR>:wincmd l<CR>

" Choose LHS file when resolving a merge conflict
nmap <leader>gf :diffget //3<CR>

" Choose RHS file when resolving a merge conflict
nmap <leader>gh :diffget //2<CR>

" Airline
" Enable powerline fonts
let g:airline_powerline_fonts = 1

 "Add NERDTree name to its buffer
let g:airline_filetype_overrides = {
    \ 'nerdtree': [ get(g:, 'NERDTreeStatusline', 'NERDTree'), '' ],
    \ }

" Truncate all path settings except the last
let g:airline#extensions#branch#format = 2

" Skip utf-8[unix] string within Airline
let g:airline#parts#ffenc#skip_expected_string='utf-8[unix]'

" Gitgutter
" Make sign column match background color
highlight! link SignColumn LineNr
let g:gitgutter_set_sign_backgrounds = 1

" Set gitgutter highlight groups
highlight GitGutterAdd    guifg=#009900 ctermfg=2
highlight GitGutterChange guifg=#bbbb00 ctermfg=3
highlight GitGutterDelete guifg=#ff2222 ctermfg=1

" Turn off sign column within Nerdtree
autocmd filetype nerdtree setlocal signcolumn=no

