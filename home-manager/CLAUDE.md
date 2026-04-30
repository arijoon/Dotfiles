# home-manager

Nix flake with two `homeConfigurations`: `arman` and `dsk`. Defined in
[`flake.nix`](flake.nix).

## Module layout

Shared by both profiles (`commonMods` in `flake.nix`):

| File                  | Purpose                                                                   |
|-----------------------|---------------------------------------------------------------------------|
| `home.nix`            | Core packages, `programs.git`, `programs.zsh`, `programs.neovim`, direnv, nix settings |
| `shell.nix`           | Nushell + Starship (vi mode, custom prompt format)                        |
| `kitty.nix`           | Kitty terminal (option `armanConfig.kitty.enable`, default `true`)        |
| `sandbox.nix`         | `sandbox-run` (landrun wrapper) and `sandbox-ai` preset for AI CLIs       |
| `common-scripts.nix`  | `update-ai` — reinstalls a CLI from `numtide/llm-agents.nix`              |
| `nixgl.nix`           | nixGL wrappers for non-NixOS GL (mesa default, nvidiaPrime offload)       |

Profile-only modules (loaded only by `arman`):

- `wsl.nix` — option `services.armanwsl.enable`. GPG pinentry for WSL.
- `xmonad.nix` — option `armanConfig.xmonad.enable`. xmobar + xmonad config from `xmonad/`.
- `emacs.nix` — option `editors.emacs.enable`. Wraps Emacs with deps; clones Doom on activation.

Per-user (`users/<name>.nix`):

- Sets `home.username`, `home.homeDirectory`, git signing key + email.
- Adds machine-specific packages.
- `arman.nix`: `yq`, `mongosh`, `alacritty`.
- `dsk.nix`: `keepassxc`, `lazydocker`, `vscode` (latest), `btop` (latest), `veracrypt`,
  `magic-wormhole`, `rclone`, plus shell apps `towebm` / `towebmnoaudio`.

## Files & assets

- `home-files/` — static config files referenced by `home.file` in `home.nix` /
  `kitty.nix` (alacritty, kitty, zellij).
- `nvim-kickstart/` — Neovim config. Linked into `~/.config/nvim/` as an
  out-of-store symlink so edits don't require a rebuild.
- `gemini/settings.json` — Gemini CLI config, also out-of-store symlinked.
- `scripts/` — shell scripts pulled in by various `.nix` modules (`sandbox-run`,
  `update-ai`, `kitty-scrollback-pager`, xmonad helpers, ffmpeg `towebm*`).
- `zsh/` — `p10k.zsh`, `fzf-completions.zsh`, `completions/kubectl.zsh`. Sourced
  from `home.nix`'s `programs.zsh.initContent`.
- `xmonad/` — Haskell xmonad/xmobar configs (only used when `xmonad.nix` is enabled).

## Inputs (flake)

- `nixpkgs` → release 25.11
- `nixpkgs-latest` → nixpkgs-unstable (exposed as `pkgs-latest`)
- `home-manager` → release 25.11
- `nix-src` (FlakeHub Nix 2.30.2) — used for `arman`
- `determinate-nix-src` (FlakeHub 3.12.0) — used for `dsk`
- `nixgl`

`extraSpecialArgs` exposes `nixpkgs`, `nixpkgs-latest`, `pkgs-latest`, `nixgl`,
and `nix` to all modules.

## Notes

- `home.stateVersion = "25.11"` — leave alone unless intentionally migrating.
- `KITTY.md` is a cheatsheet for the kitty bindings in `home-files/kitty.conf`.
- `pending.todo` is a personal TODO list.
