---
name: nixpkgs-latest-bump
description: Bump the `nixpkgs-latest` (unstable) input of home-manager/flake.lock to a newer, vetted nixpkgs revision — the pin that librewolf, kitty, mpv, vscode, worktrunk and friends are built from. Use when the user asks to update unstable packages, update librewolf/kitty/vscode, pick a newer unstable rev, or refresh nixpkgs-latest.
---

# Bumping `nixpkgs-latest`

`home-manager/flake.nix` has two nixpkgs inputs:

- `nixpkgs` — the stable release branch, moves on its own schedule.
- `nixpkgs-latest` — url tracks the `nixpkgs-unstable` branch, but the **lock is
  held at a hand-vetted revision**. Imported as `pkgs-latest` and passed to every
  profile via `extraSpecialArgs`.

The revision lives in `flake.lock` and nowhere else — `flake.nix` keeps the
branch url. The hold is deliberate: `nixpkgs-unstable` moves several times a day,
and a bad day there means a browser that does not start or a 4 GiB rebuild.
Bumping is a manual, vetted step — never a blind `nix flake update`, which would
jump straight to whatever the branch tip happens to be right now.

## Which revision to pick

Only ever pin a **channel release** of `nixpkgs-unstable`, i.e. a revision that
appears under `releases.nixos.org/nixpkgs/`. Those are exactly the revisions
where Hydra's `nixos:trunk-combined` `tested` aggregate job went green, so the
whole tested job set built. A random commit on the `nixpkgs-unstable` branch has
no such guarantee.

On top of that, prefer a rev that is:

1. **~2 weeks old** — recent enough to be worth the churn, old enough that a
   regression would already have been reported and reverted.
2. **Fully present in `cache.nixos.org`** for the packages this repo actually
   pulls from `pkgs-latest`. If a package is missing from the cache it means the
   Hydra build failed or is still running, and a switch would try to compile it
   locally (librewolf and vscode are hours of CPU).

Unfree packages (`vscode`, `veracrypt`) are *never* in `cache.nixos.org` — they
are built or fetched locally by design. The script reports them separately;
they are not a reason to reject a rev.

## The script

`check-rev.sh` automates all of the above. Run it from this directory.

```sh
cd ~/.dotfiles/.claude/skills/nixpkgs-latest-bump

./check-rev.sh list --days 30          # channel releases, newest first
./check-rev.sh pick --age-days 14      # first fully-cached rev >= 14 days old
./check-rev.sh check <rev|release>     # cache coverage for one specific rev
./check-rev.sh hydra  <rev|release>    # confirm the rev is channel-blessed
./check-rev.sh pin <rev|release>       # move flake.lock onto the rev
./check-rev.sh versions <rev>          # package versions at a rev
./check-rev.sh diff <old-rev> <new-rev># what actually changes version
```

`pick` is the whole vetting loop in one command: it walks channel releases
newest-first from the age cutoff and stops at the first one where every free
package resolves and is in the binary cache, printing `PICK <rev>`.

A `check` run takes a couple of minutes per rev — it downloads and evaluates the
full nixpkgs tree for that rev (cached in the store afterwards).

`packages.txt` is the list of attributes evaluated. It must mirror what the repo
takes from `pkgs-latest`; re-derive it after adding or removing packages:

```sh
grep -rhon "pkgs-latest\.[a-zA-Z0-9_-]*" ~/.dotfiles/home-manager --include='*.nix'
grep -rn -A20 "with pkgs-latest;" ~/.dotfiles/home-manager --include='*.nix'
```

## Applying the bump

1. Vet and choose a rev:

   ```sh
   ./check-rev.sh pick --age-days 14
   ```

2. See what will actually change, so the switch has no surprises:

   ```sh
   ./check-rev.sh diff <current-rev> <new-rev>
   ```

   The current rev is the `nixpkgs-latest` node in `home-manager/flake.lock`:

   ```sh
   nix flake metadata ~/.dotfiles/home-manager --json | jq -r '.locks.nodes["nixpkgs-latest"].locked.rev'
   ```

3. Move the lock onto the chosen rev. `flake.nix` is not touched:

   ```sh
   ./check-rev.sh pin <new-rev>
   git -C ~/.dotfiles/home-manager diff -- flake.lock
   ```

   The diff must be exactly three lines inside the `nixpkgs-latest` node —
   `lastModified`, `narHash`, `rev`. The node's `original` block keeps
   `"ref": "nixpkgs-unstable"`.

4. Dry-run the profile before switching — this is the real check that the whole
   config still evaluates and that nothing huge builds locally:

   ```sh
   cd ~/.dotfiles/home-manager
   nix build --no-link --dry-run '.#homeConfigurations.dsk.activationPackage'
   ```

   Expect a short "will be built" list: home-manager's own scripts, the wrapped
   `librewolf`/`mpv`, and the unfree packages. Anything else — especially a
   `-unwrapped` browser, a toolchain, or Qt/GTK — means the rev is not properly
   cached; go back to step 1 and take an older one.

5. Switch (**ask the user first — never run this unprompted**):

   ```sh
   nix run .#home-manager -- switch --flake '.#dsk'
   ```

## Rollback

The whole bump is three lines of `home-manager/flake.lock`, so reverting is
`git checkout -- home-manager/flake.lock` and a switch. The previous generation
is also still there: `home-manager generations`.

## Notes

- `arman` and `arlp` share the same input; check their profiles too
  (`.#homeConfigurations.arman.activationPackage`) if either machine is live.
- Nix must be able to reach `channels.nixos.org`, `releases.nixos.org`,
  `nix-releases.s3.amazonaws.com` and `cache.nixos.org` for the script to work.
- The prefix of the channel-release directories (`nixpkgs-26.11pre*`) is
  detected automatically from the current channel; override with
  `CHANNEL_PREFIX=` if a nixpkgs release rolls over mid-run.
