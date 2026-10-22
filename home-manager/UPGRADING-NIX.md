# Upgrading Nix

This flake pins both the user-facing `nix` CLI and the system `nix-daemon`.
home-manager installs the CLI; the daemon runs from root's profile, which
`upgrade-root-nix` (sudo) points at the same pins.

| Piece                | Managed by                                    | Where it lives                                                    |
|----------------------|-----------------------------------------------|-------------------------------------------------------------------|
| User `nix` binary    | home-manager (`nix.package`)                  | user profile, fed by flake inputs                                 |
| `nix-daemon` service | flake pin, applied by `upgrade-root-nix`      | root's profile, reached through `/nix/var/nix/profiles/default`   |
| `determinate-nixd`   | flake pin (`determinate` input), same script  | root's profile; `/usr/local/bin/determinate-nixd` symlinks to it  |

Root's profile follows each installer's own layout:

- Determinate (dsk): the profile is `/nix/var/nix/profiles/per-user/root/profile`
  (`profile-<n>-link` generations). `/nix/var/nix/profiles/default` and
  `/root/.nix-profile` are both symlinks to it, so the daemon and root shells
  (`sudo -i`) get the same nix.
- Upstream (arman): the profile is `/nix/var/nix/profiles/default` itself
  (`default-<n>-link` generations), and root's `~/.nix-profile` points at it.

Profiles:

- `dsk` → Determinate Nix. One knob: the `determinate` input
  (`=X.Y.Z`). `determinate-nix-src` follows `determinate/nix`, so the CLI,
  the daemon's nix and `determinate-nixd` always share a version.
  `armanConfig.rootNix.flavour = "determinate"`.
- `arman` → upstream Nix (`nix-src` input).
  `armanConfig.rootNix.flavour = "upstream"`.
- `arlp` → NixOS; the daemon is NixOS's, `upgrade-root-nix` is not installed.

## 1. Check what's installed locally

```sh
# CLI version (user-facing nix on PATH)
nix --version
# → e.g. "nix (Determinate Nix 3.12.0) 2.32.1"
#        ^ Determinate wrapper version    ^ underlying Nix version

# Daemon version — ask the running daemon directly
nix store ping --json | jq .version
# or, equivalent over the daemon socket:
nix-daemon --version

# Determinate daemon binary + service status
determinate-nixd version
systemctl status nix-daemon
systemctl cat   nix-daemon            # confirms which binary ExecStart points at

# What the user profile pins (set by `nix.package` in home.nix)
readlink -f "$(command -v nix)"
nix-store -q --references "$(readlink -f "$(command -v nix)")" | head
```

If `nix --version` and `nix store ping` disagree, the CLI was upgraded but
the daemon wasn't (or vice versa).

## 2. Check the recommended stable version

FlakeHub resolves `*` to whatever the project considers current.

```sh
# Determinate (used by dsk): the determinate flake, not nix-src. nix-src can be
# ahead of the newest determinate release, and dsk only follows determinate/nix.
curl -sSfL "https://api.flakehub.com/version/DeterminateSystems/determinate/*" | jq -r .version

# Upstream (used by arman)
curl -sSfL "https://api.flakehub.com/version/NixOS/nix/*" | jq -r .version
```

FlakeHub can lag GitHub: `NixOS/nix` 2.34.9 was a GitHub tag before FlakeHub
had it. Check `git ls-remote --tags https://github.com/NixOS/nix`; a
`github:NixOS/nix/<tag>` url works the same as the FlakeHub one.

## 3. Bump the pins and switch

Edit the pinned version in [`flake.nix`](flake.nix):

```nix
# dsk: one knob for the CLI, the daemon's nix and determinate-nixd
determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/=3.24.0";

# arman
nix-src.url = "github:NixOS/nix/2.34.9";
```

Then refresh the lock, test-build the root env, and switch:

```sh
cd ~/.dotfiles/home-manager
nix flake update determinate     # or nix-src
nix build --no-link .#root-nix-determinate     # or .#root-nix-upstream
nix run .#home-manager -- switch --flake '.#dsk'    # or .#arman
```

To always track latest instead of pinning, change `=X.Y.Z` to `*` (or a range
like `~3`). `nix flake update` then advances `flake.lock` to whatever resolves.

The switch only changes the CLI on `PATH`; builds are still performed by the
daemon, which step 4 moves.

## 4. Upgrade the `nix-daemon`

```sh
upgrade-root-nix
```

Run it as your normal user; it sudoes the privileged steps. It is installed by
`common-scripts.nix` when `armanConfig.rootNix.flavour` is set, and:

0. Determinate only: builds `root-nix-determinate` as you and stops if
   `determinate-nixd`'s own version differs from `nix --version`. The
   `determinate` flake hard-codes the daemon binary's tag but labels the
   package with its `nix` input's version, so updating `determinate/nix` (or
   `determinate-nix-src`) on its own would ship a mislabelled old daemon.
   Always bump the `determinate` input as a whole.
1. Upgrades the `root-nix-<flavour>` element of root's profile (above),
   re-resolving
   `~/.dotfiles/home-manager#root-nix-<flavour>` against `flake.lock`. On the
   first run it instead removes the installer's `nix` element (and any older
   `upstream-nix` / `determinate-nix` / `root-nix-*` element, matched by
   `attrPath` since `nix profile` names them all `home-manager` after the flake
   dir) and adds `root-nix-<flavour>`. Both run with
   `--no-update-lock-file`: a `flake.lock` that is stale against `flake.nix`
   fails instead of being re-locked by root behind home-manager's back.
2. Determinate only: points `/nix/var/nix/profiles/default` and
   `/root/.nix-profile` at `per-user/root/profile` (a no-op on the installer's
   layout), moves the installer's static `/usr/local/bin/determinate-nixd`
   aside to `determinate-nixd.installer-<version>` (first run) and symlinks
   `/usr/local/bin/determinate-nixd` → `/nix/var/nix/profiles/default/bin/determinate-nixd`.
   Each link is replaced atomically. The installer's `nix-daemon.service`
   keeps its `ExecStart`, so no unit changes.
3. `systemctl daemon-reload`, restarts `nix-daemon` and prints the daemon
   version.

Do not use `sudo determinate-nixd upgrade` any more. It fetches whatever
Determinate currently calls stable, replaces the symlink with a binary outside
the lock, and resets root's profile to its own nix (`nix-env --set`), which
drops `root-nix-<flavour>`. It also "normalizes" `default` and
`/root/.nix-profile` to `per-user/root/profile`, which is the layout this
script keeps anyway. Re-running `upgrade-root-nix` puts the pinned versions
back.

`nix` is usually not in root's `PATH` under `sudo`, so the commands below call
root's own `nix` by absolute path.

Verify:

```sh
nix store info --json | jq -r .version
determinate-nixd version
readlink -f /usr/local/bin/determinate-nixd
readlink /nix/var/nix/profiles/default /root/.nix-profile   # dsk: both per-user/root/profile
sudo /nix/var/nix/profiles/default/bin/nix profile history \
  --profile /nix/var/nix/profiles/per-user/root/profile    # arman: /nix/var/nix/profiles/default
```

Rollback (`default`, `/root/.nix-profile` and the `determinate-nixd` symlink
all go through the profile, so they roll back with it):

```sh
sudo /nix/var/nix/profiles/default/bin/nix profile rollback \
  --profile /nix/var/nix/profiles/per-user/root/profile    # arman: /nix/var/nix/profiles/default
sudo systemctl restart nix-daemon
```

On a first run the script adds `root-nix-<flavour>` (at priority 4, so it
wins over the old `nix`) before removing anything, so every generation it
creates has a working `nix` and `determinate-nixd`. Check with `nix profile
history` before rolling back past a generation made by something else.

On Determinate, generation 1 of `per-user/root/profile` is the installer's
own. To return to the installer's setup entirely, roll back to it and put the
installer's binary back:

```sh
sudo /nix/var/nix/profiles/default/bin/nix profile rollback \
  --profile /nix/var/nix/profiles/per-user/root/profile --to 1
sudo mv /usr/local/bin/determinate-nixd.installer-<version> /usr/local/bin/determinate-nixd
sudo systemctl restart nix-daemon
```

This puts the daemon back on whatever the installer last laid down, e.g.
3.12.0 here, which predates the 2026 Nix advisories. Follow it straight away
with `sudo determinate-nixd upgrade` (or the installer fallback below) if you
are leaving the flake-managed setup, or re-run `upgrade-root-nix` to return
to it.

Fallback if `determinate-nixd` itself is broken — re-run the installer in
upgrade mode:

```sh
curl -fsSL https://install.determinate.systems/nix/upgrade | sh
```

On an upstream multi-user install the unit's `ExecStart` points at
`/nix/var/nix/profiles/default/bin/nix-daemon` directly, so step 1 is all
it takes.

### What the installer does (and when you actually need it)

`sh <(curl -L https://nixos.org/nix/install) --daemon` is a full bootstrap,
not just a version bump. It:

1. Creates `/nix` (and on macOS, the synthetic volume + APFS setup).
2. Creates the `nixbld` group and the `nixbld1..nixbld32` build users.
3. Copies the new Nix closure into `/nix/store` and installs it into
   `/nix/var/nix/profiles/default` (root's profile — the one the daemon runs
   from).
4. Writes `/etc/nix/nix.conf` (only on a fresh install; existing one is
   preserved).
5. Installs the systemd unit `nix-daemon.service` (and socket) pointing at
   `/nix/var/nix/profiles/default/bin/nix-daemon`, then enables/starts it.
6. Adds shell init: `/etc/profile.d/nix.sh`, snippets in `/etc/bashrc`,
   `/etc/zshrc`, `/etc/bash.bashrc` (backed up as `*.backup-before-nix`).
7. Sets up `tmpfiles.d` entries so `/nix/var/nix/...` is recreated on boot.

For a routine version bump on an already-installed system, **none of (1), (2),
(6), (7) need to change** — upgrading root's profile + restarting the daemon
is enough. Re-run the installer only when:

- The systemd unit / socket definition itself changed between releases (rare;
  release notes will say so).
- `nixbld` user/group setup got out of sync (e.g. you nuked `/etc/passwd`
  entries).
- Shell init snippets in `/etc/profile.d/nix.sh` need refreshing.
- You're migrating between installer flavours (upstream ↔ Determinate).

In all other cases the `sudo nix profile upgrade … && systemctl restart
nix-daemon` path is what the installer would have done anyway, just without
touching the surrounding system bits.

## Keeping CLI and daemon in sync

`flake.lock` is the single source of truth for both. The order is:

1. Bump the pin in `flake.nix`, `nix flake update determinate` (or `nix-src`).
   Never `nix flake update determinate-nix-src` or `determinate/nix` alone;
   `upgrade-root-nix` refuses the result.
2. `nix run .#home-manager -- switch --flake '.#dsk'` — the CLI.
3. `upgrade-root-nix` — the daemon.

Wire compatibility across nearby releases is fine, so the window between 2
and 3 is harmless. `determinate-nixd version` warns if client and daemon
differ.
