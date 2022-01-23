" Spacevim configuration
function! myspacevim#before() abort
  " SimpylFold
  let g:SimpylFold_docstring_preview = 1 

  " " Symbols config
  let g:airline_powerline_fonts=1
  let g:airline_theme='angr'

endfunction

function! myspacevim#after() abort

  " Indent config
  set smartindent
  set tabstop=2
  set shiftwidth=2
  set expandtab
  set nu
  set nocompatible
  set backspace=2

  set laststatus=2   " Always show the statusline
  set encoding=utf-8 " Necessary to show Unicode glyphs
  set t_Co=256 " Explicitly tell Vim that the terminal supports 256 colors

  set splitbelow
  set splitright

  set foldmethod=indent
  set foldlevel=99

  nnoremap <Leader>p "0p
  inoremap jj <ESC>


endfunction
