let g:arman = {}
func! arman#launch() abort

  let l:sectors = [
        \ 'plugins',
        \ 'theme',
        \ ]

  for sector in l:sectors
    exe 'call arman#' . l:sector . '#setup()'
  endfor
endfunc
