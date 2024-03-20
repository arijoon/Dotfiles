# Nix notes

## Finding source
`nix edit` is the shell command
`.meta.position` if the attribute has meta
`builtins.unsafeGetAttrPos` to find the location in the source code

## Show full output in repl
Use `:p`

## Sorepath antipattern
`builtins.storePath`, use `builtins.getContext` to inpect