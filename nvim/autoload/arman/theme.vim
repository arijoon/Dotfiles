func! arman#theme#setup()
  let base16colorspace=256
  set termguicolors
  "if filereadable(expand("~/.vimrc_background"))
    "source ~/.vimrc_background
  "else
  colorscheme base16-summerfruit-dark
  "AirlineTheme simple
endfunc
