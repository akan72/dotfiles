syntax on

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

set colorcolumn=80

call plug#begin('~/.vim/.plugged')

Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'VundleVim/Vundle.vim'
Plug 'flazz/vim-colorschemes'
Plug 'ervandew/supertab'
Plug 'preservim/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'

call plug#end()

colorscheme gruvbox
let g:gruvbox_contrast_dark = 'hard'
set background=dark

vmap <C-c> "+y
let mapleader = "\<Space>"
let g:netrw_browse_split = 2
let g:netrw_winsize = 25
let g:netrw_banner = 0

" Append and prepend blank lines with <leader>?<Enter>
nnoremap <Enter> :call append(line('.'), '')<CR>
nnoremap <leader><Enter> :call append(line('.')-1, '')<CR>

nnoremap <leader>h :wincmd h<CR>
nnoremap <leader>j :wincmd j<CR>
nnoremap <leader>k :wincmd k<CR>
nnoremap <leader>l :wincmd l<CR>

nnoremap <leader>f :NERDTreeToggle<CR>
" let g:NERDTreeChDirMode = 2
let NERDTreeMinimalUI = 1
let NERDTreeDirArrows = 1

" NERDTress File highlighting
function! NERDTreeHighlightFile(extension, fg, bg, guifg, guibg)
    exec 'autocmd filetype nerdtree highlight ' . a:extension .' ctermbg='. a:bg .' ctermfg='. a:fg .' guibg='. a:guibg .' guifg='. a:guifg
    exec 'autocmd filetype nerdtree syn match ' . a:extension .' #^\s\+.*'. a:extension .'$#'
endfunction

    call NERDTreeHighlightFile('jade', 'green', 'none', 'green', '#151515')
    call NERDTreeHighlightFile('ini', 'yellow', 'none', 'yellow', '#151515')
    call NERDTreeHighlightFile('md', 'blue', 'none', '#3366FF', '#151515')
    call NERDTreeHighlightFile('yml', 'yellow', 'none', 'yellow', '#151515')
    call NERDTreeHighlightFile('config', 'yellow', 'none', 'yellow','#151515')
    call NERDTreeHighlightFile('conf', 'yellow', 'none', 'yellow', '#151515')
    call NERDTreeHighlightFile('json', 'yellow', 'none', 'yellow', '#151515')
    call NERDTreeHighlightFile('html', 'yellow', 'none', 'yellow', '#151515')
    call NERDTreeHighlightFile('styl', 'cyan', 'none', 'cyan', '#151515')
    call NERDTreeHighlightFile('css', 'cyan', 'none', 'cyan', '#151515')
    call NERDTreeHighlightFile('coffee', 'Red', 'none', 'red', '#151515')
    call NERDTreeHighlightFile('js', 'Red', 'none', '#ffa500', '#151515')
    call NERDTreeHighlightFile('php', 'Magenta', 'none', '#ff00ff', '#151515')

" Automatically open nerdtree on startup, but move cursor to main window
autocmd VimEnter * NERDTree 
autocmd VimEnter * wincmd p

" Automatically close nerdtree if it's the last buffer
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

" Remove preview window in jedi-vim
" autocmd FileType python setlocal completeopt-=preview

