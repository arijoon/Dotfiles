# Upgrading Nix

This flake pins both the user-facing `nix` CLI and (indirectly) which Nix
flavour each profile uses. The system `nix-daemon` is **separate** and not
managed by home-manager.

| Piece                | Managed by                       | Where it lives                          |
|----------------------|----------------------------------|-----------------------------------------|
| User `nix` binary    | home-manager (`nix.package`)     | user profile, fed by flake inputs       |
| `nix-daemon` service | Determinate installer / upstream | `/usr/local/bin/determinate-nixd` etc.  |

Profiles:

- `dsk` → Determinate Nix (`determinate-nix-src` input)
- `arman` → upstream Nix (`nix-src` input)

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
# Determinate (used by dsk)
curl -sSfL "https://api.flakehub.com/version/DeterminateSystems/nix-src/*" | jq -r .version

# Upstream (used by arman)
curl -sSfL "https://api.flakehub.com/version/NixOS/nix/*" | jq -r .version
```

For the daemon specifically, `determinate-nixd upgrade` defaults to
`--version stable` and will pick the version Determinate currently advises.

## 3. Upgrade the user-facing `nix` CLI

Edit the pinned version in [`flake.nix`](flake.nix):

```nix
# dsk profile
determinate-nix-src.url = "https://flakehub.com/f/DeterminateSystems/nix-src/=3.19.0";

# arman profile
nix-src.url = "https://flakehub.com/f/NixOS/nix/=2.34.6";
```

Then refresh the lock and switch:

```sh
cd ~/.dotfiles/home-manager
nix flake update determinate-nix-src     # or nix-src
nix run .#home-manager -- switch --flake '.#dsk'    # or .#arman
```

To always track latest instead of pinning, change `=X.Y.Z` to `*` (or a range
like `~3`). `nix flake update` then advances `flake.lock` to whatever resolves.

This only changes the CLI on `PATH`; builds are still performed by the daemon.

## 4. Upgrade the `nix-daemon`

The daemon binary is installed outside `/nix/store` and is **not** controlled
by this flake.

### Determinate daemon (this machine)

```sh
sudo determinate-nixd upgrade            # --version stable by default
# or pin: sudo determinate-nixd upgrade --version 3.19.0
```

The service restarts automatically. Verify:

```sh
nix --version
systemctl status nix-daemon
```

Fallback if `determinate-nixd` itself is broken — re-run the installer in
upgrade mode:

```sh
curl -fsSL https://install.determinate.systems/nix/upgrade | sh
```

### Upstream multi-user daemon

The daemon's `ExecStart` on an upstream multi-user install points at
`/nix/var/nix/profiles/default/bin/nix-daemon` — i.e. **root's `default`
profile**. So a version bump is just upgrading that profile and restarting
the service:

The flake exposes the pinned upstream Nix derivation as
`packages.x86_64-linux.upstream-nix` ([`flake.nix`](flake.nix)), so root's
profile can be pointed at the **same** Nix version the flake uses for the
`arman` user CLI — one source of truth.

`nix` is usually not in root's `PATH` under `sudo`, so call the binaries
from root's default profile by absolute path. `~` also expands to `/root`
under `sudo`, so spell out the flake path too.

First-time switch (replaces the installer-provided `nix` entry in root's
default profile with the flake-pinned `upstream-nix`):

```sh
# 1. find the existing nix entry's index/name
sudo /nix/var/nix/profiles/default/bin/nix profile list \
  --profile /nix/var/nix/profiles/default

# 2. remove it (use the index or name from the list above)
sudo /nix/var/nix/profiles/default/bin/nix profile remove \
  --profile /nix/var/nix/profiles/default nix

# 3. install the flake's upstream-nix into root's default profile
sudo /nix/var/nix/profiles/default/bin/nix profile install \
  --profile /nix/var/nix/profiles/default \
  /home/dsk/.dotfiles/home-manager#upstream-nix

sudo systemctl daemon-reload
sudo systemctl restart nix-daemon
nix store ping --json | jq .version       # confirm new daemon version
```

Subsequent upgrades — bump the flake input and re-resolve the profile entry
against the new lock:

```sh
cd ~/.dotfiles/home-manager
nix flake update nix-src                  # advance the pin

sudo /nix/var/nix/profiles/default/bin/nix profile upgrade \
  --profile /nix/var/nix/profiles/default \
  upstream-nix

sudo systemctl daemon-reload
sudo systemctl restart nix-daemon
nix store ping --json | jq .version
```

`nix profile upgrade upstream-nix` re-evaluates the same flake reference the
entry was installed from, so it always picks up whatever
`/home/dsk/.dotfiles/home-manager#upstream-nix` currently resolves to.

#### What the installer does (and when you actually need it)

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

Wire compatibility across nearby releases is fine, so exact match isn't
required, but the tidy order for `dsk` is:

1. `sudo determinate-nixd upgrade` — bumps the daemon.
2. Bump `determinate-nix-src` pin in `flake.nix` to the matching `3.x.y`.
3. `nix flake update determinate-nix-src && home-manager switch --flake '.#dsk'`.

The daemon is what actually executes builds, so its version is the one that
changes behaviour for `nix build` / `nix run`.
