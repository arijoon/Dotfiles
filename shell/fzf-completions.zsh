# Fzf custom autocompletions
_fzf_complete_printenv() {
  _fzf_complete -m -- "$@" < <(
    declare -xp | sed 's/=.*//' | sed 's/.* //'
  )
}

