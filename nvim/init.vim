let g:SimpylFold_docstring_preview = 1 
autocmd BufWinEnter *.py setlocal foldexpr=SimpylFold(v:lnum) foldmethod=expr
autocmd BufWinLeave *.py setlocal foldexpr< foldmethod<
" Fix indentation to 2 spaces
set smartindent
set tabstop=2
set shiftwidth=2
set expandtab
set nu
set nocompatible
"set backspace=2

"set laststatus=2   " Always show the statusline
"set encoding=utf-8 " Necessary to show Unicode glyphs
"set t_Co=256 " Explicitly tell Vim that the terminal supports 256 colors

set splitbelow
set splitright

set foldmethod=indent
set foldlevel=99

"set background=dark
"color peachpuff

" Mapping
"no <down> ddp
"no <up> ddkP
"no <left> gT
"no <right> gt

noremap <space> za
noremap <C-q> <C-v>

" Window navigation
nmap <silent> <A-Up> :wincmd k<CR>
nmap <silent> <A-Down> :wincmd j<CR>
nmap <silent> <A-Left> :wincmd h<CR>
nmap <silent> <A-Right> :wincmd l<CR>

" CTRL-X is Cut
vnoremap <C-C> "+y
vnoremap <leader>p "+p 

" CTRL-C is Copy
vnoremap <C-C> "+y
vnoremap <leader>y "+y 

" adding syntax highlighting for all *.md files
au BufRead,BufNewFile *.md set filetype=markdown

" Mapping VisualStudio commands
"nnoremap <Leader>i :vsc Resharper.Resharper_GoToImplementation<CR>
"nnoremap <Leader>f :vsc Resharper.Resharper_GoToFile<CR>
"nnoremap <Leader>u :vsc Resharper.Resharper_FindUsages<CR>
"nnoremap <Leader>d :vsc Resharper.Resharper_GoToDeclaration<CR>
"nnoremap <Leader>gb :vsc Resharper.Resharper_NavigateBackward<CR>
"nnoremap <Leader>rt :vsc Resharper.Resharper_RefactorThis<CR>
nnoremap <Leader>p "0p
inoremap jj <ESC>

let g:airline_powerline_fonts=1
let g:Powerline_symbols='unicode'
set encoding=utf-8
let g:airline_powerline_fonts=1
"set guifont=Source\ Code\ Pro\ for\ Powerline:h11
set guifont=Courier_New:h11

call arman#launch()
