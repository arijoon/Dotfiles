# Dotfiles

Personal dotfiles. Linux (Manjaro) + occasional WSL. Primary user `dsk`; secondary
`arman` (work machine).

## What's active

Everything currently in use lives under [`home-manager/`](home-manager/) as a Nix
flake with Home Manager. Two profiles share most modules:

- `arman` — work machine. Adds WSL, XMonad, Emacs (Doom).
- `dsk` — personal. Plain home-manager + extra desktop apps.

See [`home-manager/CLAUDE.md`](home-manager/CLAUDE.md) for the module map.

## Apply changes

```sh
cd ~/.dotfiles/home-manager
nix run .#home-manager -- switch --flake '.#dsk'
```

`~/.config/home-manager` is symlinked to `~/.dotfiles/home-manager` by the
installer (`install.arijoon.hm.sh`).

## What to ignore

These are old/abandoned configs kept in the tree but not used. **Do not read or
suggest edits to these unless the user asks specifically.**

- `vim/`, `.vim` (symlink), `.Spacevim.d/` — old vim setups
- `nvim/` — old neovim entrypoint; the live config is `home-manager/nvim-kickstart/`
- `vs-code/`, `cmder/`, `.zsh/` — superseded by home-manager modules
- `install.arijoon.sh`, top-level `README.md` — pre-home-manager bootstrap

## Conventions

- Nix formatter: `nixfmt-rfc-style` (run `nixfmt` on edited files).
- nixpkgs is pinned to release `25.11`; `nixpkgs-latest` is unstable, used for
  selected packages (`worktrunk`, `landrun`, `kitty`, `vscode`, `btop`, ...).
- Custom module options live under `armanConfig.*`, `editors.*`, or
  `services.armanwsl`.
- Shell scripts go in `home-manager/scripts/` and are wrapped via
  `pkgs.writeShellApplication` (preferred) or `writeShellScriptBin`.
