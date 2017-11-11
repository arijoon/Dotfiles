" Options {{{
let g:arman.plugins = {
      \ 'root': expand('~/.config/nvim/plugins'),
      \ }
" }}}

func! arman#plugins#setup() " {{{
  call arman#plugins#define()
  call arman#plugins#configure()
  call arman#plugins#configure_mappings()

  filetype plugin indent on
  syntax on

  if exists('$NVIM_VERBOSE')
    let $NVIM_PYTHON_LOG_FILE=expand('~/.config/nvim/logs/python.log')
  endif
endfunc " }}}

func! arman#plugins#define() abort " {{{
  call plug#begin(g:arman.plugins.root)

  Plug 'chriskempson/base16-vim'
  Plug 'https://github.com/eagletmt/ghcmod-vim.git'
  Plug 'https://github.com/scrooloose/nerdtree.git'
  Plug 'https://github.com/Lokaltog/vim-easymotion.git'
  "Plug 'https://github.com/Lokaltog/vim-powerline.git'
  Plug 'https://github.com/tpope/vim-fugitive.git'
  Plug 'https://github.com/scrooloose/syntastic.git'
  Plug 'https://github.com/othree/html5.vim.git'
  Plug 'https://github.com/tpope/vim-rails.git'
  Plug 'https://github.com/tpope/vim-bundler.git'
  Plug 'https://github.com/scrooloose/nerdcommenter.git'
  Plug 'https://github.com/kchmck/vim-coffee-script.git'
  Plug 'https://github.com/altercation/vim-colors-solarized.git'
  Plug 'https://github.com/jistr/vim-nerdtree-tabs.git'
  Plug 'https://github.com/OrangeT/vim-csharp.git'
  Plug 'https://github.com/vim-airline/vim-airline.git'
  Plug 'vim-airline/vim-airline-themes'
  Plug 'vim-airline/vim-airline-themes'
  Plug 'https://github.com/fatih/vim-go.git'
  Plug 'https://github.com/Blackrush/vim-gocode.git'
  Plug 'https://github.com/tmhedberg/SimpylFold.git'
  Plug 'https://github.com/dzeban/vim-log-syntax.git'

  call plug#end()
endfunc

func! arman#plugins#configure() abort " {{{
  let g:go_highlight_functions = 1
  let g:go_highlight_methods = 1
  let g:go_highlight_fields = 1
  let g:go_highlight_structs = 1
  let g:go_highlight_interfaces = 1
  let g:go_highlight_operators = 1
  let g:go_highlight_build_constraints = 1

  let g:go_fmt_command = "goimports"


  let g:SimpylFold_docstring_preview = 1 
  autocmd BufWinEnter *.py setlocal foldexpr=SimpylFold(v:lnum) foldmethod=expr


  autocmd BufWinLeave *.py setlocal foldexpr< foldmethod<
endfunc "}}}

func! arman#plugins#configure_mappings() abort
  map <C-n> : NERDTreeToggle<CR> 
endfunc
