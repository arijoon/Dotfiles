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
| `common-scripts.nix`  | `update-ai` — reinstalls a CLI from `numtide/llm-agents.nix`. `upgrade-root-nix` (option `armanConfig.rootNix.flavour`: `determinate` on `dsk`, `upstream` on `arman`) — moves root's profile, i.e. the nix-daemon, onto the flake's `root-nix-<flavour>`. For Determinate that is `per-user/root/profile`, with `/nix/var/nix/profiles/default`, `/root/.nix-profile` and `/usr/local/bin/determinate-nixd` symlinked into it; for upstream it is `/nix/var/nix/profiles/default`. See `UPGRADING-NIX.md` |
| `nixgl.nix`           | nixGL wrappers for non-NixOS GL (mesa default, nvidiaPrime offload)       |
| `mpv.nix`             | mpv player (option `armanConfig.mpv.enable`, default `false`; on for `dsk`). Latest mpv + nixGL, re-wrapped so ffmpeg + subliminal are on mpv's PATH only (not the profile) and `~/.config/mpv/secrets.env` is sourced for script creds. Config from `home-files/mpv/` |
| `ai/`                  | AI tooling. Claude itself stays a `nix profile` install (`update-ai`); HM never manages its binary, settings or `~/.claude` dirs, it only links skills: each is an out-of-store symlink `~/.claude/skills/<name>` → this repo, so edits land here. `ai/ralph/` (option `armanConfig.ai.ralph.enable`; on for `dsk`): the `ralph` loop command (`ralph.sh`, default prompts in `templates/`; it runs whatever agent command it is given and sandboxes nothing) and its skill (`skill/`, with per-agent notes in `skill/references/`). `test.sh` is the stubbed scenario suite, run against the installed `ralph`: `bash ai/ralph/test.sh`. `ai/opencode/` (option `armanConfig.ai.opencode.enable`; on for `arman`): the regular `opencode`, wrapped and configured for a llama.cpp llama-server at `$LLAMA_SERVER` (default `vopono.host:5001` inside `with-vpn -H`, else `127.0.0.1:5001`), with a small never-refusing prompt (`prompt.md`) and a SearXNG search tool at `$SEARXNG_URL`; testing it: the `opencode` skill |

Profile-only modules (loaded only by `arman`):

- `wsl.nix` — option `services.armanwsl.enable`. GPG pinentry for WSL.
- `xmonad.nix` — option `armanConfig.xmonad.enable`. xmobar + xmonad config from `xmonad/`.
- `emacs.nix` — option `editors.emacs.enable`. Wraps Emacs with deps; clones Doom on activation.

Per-user (`users/<name>.nix`):

- Sets `home.username`, `home.homeDirectory`, git signing key + email.
- Adds machine-specific packages.
- `arman.nix`: `yq`, `mongosh`, `alacritty`.
- `dsk.nix`: `keepassxc`, `lazydocker`, `vscode` (latest), `btop` (latest), `veracrypt`,
  `magic-wormhole`, `rclone`, `zmx`, `herdr`, plus shell apps `towebm` / `towebmnoaudio`.

## Files & assets

- `home-files/` — static config files referenced by `home.file` in `home.nix` /
  `kitty.nix` (alacritty, kitty, zellij). `home-files/mpv/` holds the mpv config
  (`mpv.conf`, `input.conf`, `script-opts/`, lua `scripts/`), symlinked by `mpv.nix`.
  `home-files/herdr/config.toml` is herdr's config (prefix `ctrl+a`, keys mirroring
  `kitty.conf`'s `kitty_mod` maps), out-of-store symlinked by `users/dsk.nix`.
- `nvim-kickstart/` — Neovim config. Linked into `~/.config/nvim/` as an
  out-of-store symlink so edits don't require a rebuild.
- `gemini/settings.json` — Gemini CLI config, also out-of-store symlinked.
- `scripts/` — shell scripts pulled in by various `.nix` modules (`sandbox-run`,
  `update-ai`, `kitty-scrollback-pager`, xmonad helpers, ffmpeg `towebm*`).
- `zsh/` — `p10k.zsh`, `fzf-completions.zsh`, `completions/kubectl.zsh`. Sourced
  from `home.nix`'s `programs.zsh.initContent`.
- `xmonad/` — Haskell xmonad/xmobar configs (only used when `xmonad.nix` is enabled).

## Inputs (flake)

- `nixpkgs` → `nixos-26.05` channel branch (not the frozen `26.05` tag)
- `nixpkgs-latest` → nixpkgs-unstable (exposed as `pkgs-latest`). The url tracks
  the branch but the lock is held at a hand-vetted channel release — bump it via
  the `nixpkgs-latest-bump` skill, not `nix flake update`.
- `nixpkgs-vopono` → nixpkgs pinned by rev in the url (`391b592e…`, vopono 0.10.19),
  exposed as `pkgs-vopono` and used only by `network.nix`. vopono 1.0.x leaks the
  namespace + openvpn on exit (drops its lockfile but skips teardown), so the next
  `with-vpn` on the same server fails until openvpn is killed
- `home-manager` → release 26.05
- `nix-src` (`github:NixOS/nix/2.34.9`) — used for `arman`
- `determinate` (FlakeHub `=3.24.0`) — `determinate-nixd` for `dsk`'s daemon; `determinate-nix-src` follows its `nix`, so this one pin sets dsk's CLI and daemon
- `nixgl`
- `zmx`, `herdr` (pinned to a release tag; bump by editing the tag in the url) —
  `dsk` only, passed to `users/dsk.nix` via its `extraSpecialArgs`

`extraSpecialArgs` exposes `nixpkgs`, `nixpkgs-latest`, `pkgs-latest`, `pkgs-vopono`, `nixgl`,
and `nix` to all modules.

## Notes

- `home.stateVersion = "25.11"` — leave alone unless intentionally migrating.
- `KITTY.md` is a cheatsheet for the kitty bindings in `home-files/kitty.conf`.
- `pending.todo` is a personal TODO list.
- Login shell must be the nix zsh (`~/.nix-profile/bin/zsh` via `chsh`) so its
  dynamic deps (nix glibc) match nix-built modules like fzf-tab's `fzftab.so`.
