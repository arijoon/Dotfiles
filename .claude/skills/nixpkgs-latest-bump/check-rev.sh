#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_FILE="${PKG_FILE:-$SELF_DIR/packages.txt}"
SYSTEM="${SYSTEM:-x86_64-linux}"
BUCKET="https://nix-releases.s3.amazonaws.com"
CACHE="${CACHE:-https://cache.nixos.org}"
CHANNEL_PREFIX="${CHANNEL_PREFIX:-}"
FLAKE_DIR="${FLAKE_DIR:-$SELF_DIR/../../../home-manager}"
INPUT="${INPUT:-nixpkgs-latest}"

usage() {
  cat <<'USAGE'
check-rev.sh — vet nixpkgs-unstable revisions before pinning nixpkgs-latest

  list [--days N] [--max N]
        Channel releases (Hydra-blessed nixpkgs-unstable bumps), newest first.
        --days N   only releases from the last N days (default 30)
        --max N    cap rows printed (default 40)

  check REV...
        For each rev, evaluate every package in packages.txt and report how many
        output paths are already in cache.nixos.org.

  pick [--age-days N] [--tries N]
        Walk channel releases at least N days old (default 14), newest first,
        and report the first one with full binary-cache coverage.

  versions REV
        Print name -> version for every package in packages.txt at REV.

  diff OLD NEW
        Show which packages change version between two revs.

  pin REV
        Rewrite only the locked entry of the nixpkgs-latest input in
        home-manager/flake.lock to REV. flake.nix keeps its branch url.

  hydra REV
        Confirm REV is a published channel release (i.e. the trunk-combined
        'tested' aggregate was green) and link its Hydra eval when still listed.

Env: PKG_FILE, SYSTEM, CACHE, CHANNEL_PREFIX, FLAKE_DIR, INPUT
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

detect_prefix() {
  if [[ -n "$CHANNEL_PREFIX" ]]; then
    echo "$CHANNEL_PREFIX"
    return
  fi
  local latest
  latest=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://channels.nixos.org/nixpkgs-unstable) ||
    die "cannot reach channels.nixos.org"
  basename "$latest" | sed 's/^\(nixpkgs-[0-9.]*pre\).*/\1/'
}

releases() {
  local prefix
  prefix=$(detect_prefix)
  python3 - "$BUCKET" "$prefix" <<'PY'
import re, sys, urllib.parse, urllib.request

bucket, prefix = sys.argv[1], sys.argv[2]
token, rows = None, []
while True:
    query = {"list-type": "2", "prefix": f"nixpkgs/{prefix}", "max-keys": "1000"}
    if token:
        query["continuation-token"] = token
    body = urllib.request.urlopen(f"{bucket}/?{urllib.parse.urlencode(query)}", timeout=60).read().decode()
    for key, date in re.findall(r"<Key>([^<]*)</Key><LastModified>([^<]*)</LastModified>", body):
        if key.endswith("/git-revision"):
            rows.append((date, key.split("/")[1]))
    more = re.search(r"<NextContinuationToken>([^<]*)", body)
    if "<IsTruncated>true" in body and more:
        token = more.group(1)
    else:
        break
for date, name in sorted(rows, reverse=True):
    print(date[:10], name)
PY
}

full_rev() {
  local name=$1
  curl -fsSL "https://releases.nixos.org/nixpkgs/$name/git-revision"
  echo
}

cmd_list() {
  local days=30 max=40
  while [[ $# -gt 0 ]]; do
    case $1 in
    --days)
      days=$2
      shift 2
      ;;
    --max)
      max=$2
      shift 2
      ;;
    *) die "unknown flag $1" ;;
    esac
  done
  local cutoff
  cutoff=$(date -u -d "$days days ago" +%F)
  releases | awk -v c="$cutoff" '$1 >= c' | head -n "$max"
}

eval_paths() {
  local rev=$1 names
  names=$(python3 -c 'import sys; print("[ " + " ".join(chr(34)+l.strip()+chr(34) for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")) + " ]")' "$PKG_FILE")
  nix eval --json --extra-experimental-features 'nix-command flakes' --expr "
    let
      pkgs = import (builtins.getFlake \"github:nixos/nixpkgs/$rev\") {
        system = \"$SYSTEM\";
        config.allowUnfree = true;
      };
      probe = name:
        let
          drv = builtins.tryEval (builtins.getAttr name pkgs);
          path = if drv.success then builtins.tryEval drv.value.outPath else drv;
          unfree = drv.success && ((drv.value.meta or { }).unfree or false);
        in {
          name = name;
          value = if path.success then { path = path.value; unfree = unfree; } else null;
        };
    in builtins.listToAttrs (map probe $names)
  "
}

cmd_check() {
  [[ $# -gt 0 ]] || die "check needs at least one rev"
  local input rev
  for input in "$@"; do
    rev=$input
    [[ $rev == nixpkgs-* ]] && rev=$(full_rev "$rev")
    echo "== $rev"
    local json
    json=$(eval_paths "$rev") || die "eval failed for $rev"

    local total=0 hit=0 missing=() broken=() unfree=()
    while IFS=$'\t' read -r name flag path; do
      if [[ $path == null || -z $path ]]; then
        broken+=("$name")
        continue
      fi
      if [[ $flag == unfree ]]; then
        unfree+=("$name")
        continue
      fi
      total=$((total + 1))
      local hash=${path#/nix/store/}
      hash=${hash%%-*}
      if curl -fs -o /dev/null --max-time 20 "$CACHE/$hash.narinfo"; then
        hit=$((hit + 1))
      else
        missing+=("$name")
      fi
    done < <(python3 -c 'import json,sys
for k, v in json.load(sys.stdin).items():
    if v is None: print(k, "-", "null", sep="\t")
    else: print(k, "unfree" if v["unfree"] else "free", v["path"], sep="\t")' <<<"$json")

    echo "   cached  $hit/$total"
    ((${#missing[@]})) && echo "   missing ${missing[*]}"
    ((${#broken[@]})) && echo "   noeval  ${broken[*]}"
    ((${#unfree[@]})) && echo "   unfree  ${unfree[*]} (never in cache.nixos.org, built locally)"
    if ((${#missing[@]} == 0 && ${#broken[@]} == 0)); then
      echo "   VERDICT ok"
    else
      echo "   VERDICT needs-review"
    fi
  done
}

cmd_pick() {
  local age=14 tries=5
  while [[ $# -gt 0 ]]; do
    case $1 in
    --age-days)
      age=$2
      shift 2
      ;;
    --tries)
      tries=$2
      shift 2
      ;;
    *) die "unknown flag $1" ;;
    esac
  done
  local cutoff
  cutoff=$(date -u -d "$age days ago" +%F)
  local candidates=()
  mapfile -t candidates < <(releases | awk -v c="$cutoff" '$1 <= c' | head -n "$tries")
  ((${#candidates[@]})) || die "no channel release older than $age days found"
  local row date name rev out
  for row in "${candidates[@]}"; do
    date=${row%% *}
    name=${row##* }
    rev=$(full_rev "$name")
    echo "-- candidate $date $name"
    out=$(cmd_check "$rev" </dev/null)
    echo "$out" | sed 's/^/   /'
    if grep -q 'VERDICT ok' <<<"$out"; then
      echo
      echo "PICK $rev  ($date, $name)"
      return 0
    fi
  done
  die "no fully-cached candidate in the last $tries tries"
}

eval_versions() {
  local rev=$1 names
  names=$(python3 -c 'import sys; print("[ " + " ".join(chr(34)+l.strip()+chr(34) for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")) + " ]")' "$PKG_FILE")
  nix eval --json --extra-experimental-features 'nix-command flakes' --expr "
    let
      pkgs = import (builtins.getFlake \"github:nixos/nixpkgs/$rev\") {
        system = \"$SYSTEM\";
        config.allowUnfree = true;
      };
      probe = name:
        let v = builtins.tryEval (builtins.getAttr name pkgs).version;
        in { name = name; value = if v.success then v.value else \"?\"; };
    in builtins.listToAttrs (map probe $names)
  "
}

resolve_rev() {
  local rev=$1
  [[ $rev == nixpkgs-* ]] && rev=$(full_rev "$rev")
  echo "$rev"
}

cmd_versions() {
  local rev
  rev=$(resolve_rev "${1:?versions needs a rev}")
  eval_versions "$rev" | python3 -c 'import json,sys
for k, v in sorted(json.load(sys.stdin).items()): print(f"{k:<16} {v}")'
}

cmd_diff() {
  local old new
  old=$(resolve_rev "${1:?diff needs OLD NEW}")
  new=$(resolve_rev "${2:?diff needs OLD NEW}")
  python3 -c 'import json,sys
old, new = json.loads(sys.argv[1]), json.loads(sys.argv[2])
for k in sorted(old):
    if old[k] != new.get(k): print(f"{k:<16} {old[k]}  ->  {new.get(k)}")
' "$(eval_versions "$old")" "$(eval_versions "$new")"
}

cmd_pin() {
  local rev lock info
  rev=$(resolve_rev "${1:?pin needs a rev}")
  local dir
  dir=$(realpath "$FLAKE_DIR")
  lock="$dir/flake.lock"
  [[ -f $lock ]] || die "no flake.lock at $lock"
  info=$(nix eval --json --extra-experimental-features 'nix-command flakes' --expr "
    let flake = builtins.getFlake \"github:nixos/nixpkgs/$rev\";
    in { narHash = flake.narHash; lastModified = flake.lastModified; }
  ") || die "cannot resolve github:nixos/nixpkgs/$rev"
  python3 - "$lock" "$INPUT" "$rev" "$info" <<'PYPIN'
import json, sys

lock_path, input_name, rev, info = sys.argv[1:5]
info = json.loads(info)
lock = json.loads(open(lock_path).read())
node = lock["nodes"].get(input_name)
if node is None:
    sys.exit("error: no input %r in %s" % (input_name, lock_path))
locked = node["locked"]
before = locked.get("rev")
locked["lastModified"] = info["lastModified"]
locked["narHash"] = info["narHash"]
locked["rev"] = rev
open(lock_path, "w").write(json.dumps(lock, indent=2, sort_keys=True) + "\n")
print("%s: %s -> %s" % (input_name, before, rev))
PYPIN
  echo "flake.nix untouched; review with: git -C $dir diff -- flake.lock"
}

cmd_hydra() {
  local rev
  rev=$(resolve_rev "${1:?hydra needs a rev}")
  local short=${rev:0:12} row
  row=$(releases | grep -- "$short" || true)
  if [[ -n $row ]]; then
    echo "channel release: $row"
    echo "  nixos:trunk-combined 'tested' aggregate was green for this rev"
    echo "  https://releases.nixos.org/nixpkgs/${row##* }/"
  else
    echo "$rev is NOT a published nixpkgs-unstable channel release"
    echo "  (plain branch commits are not Hydra-blessed; prefer a rev from 'list')"
  fi
  curl -fsSL --max-time 60 -H 'Accept: application/json' \
    'https://hydra.nixos.org/jobset/nixos/trunk-combined/evals' |
    python3 -c '
import json, sys

rev = sys.argv[1]
for ev in json.load(sys.stdin).get("evals", []):
    got = (ev.get("jobsetevalinputs", {}).get("nixpkgs") or {}).get("revision") or ""
    if got and (got.startswith(rev) or rev.startswith(got)):
        print("  eval https://hydra.nixos.org/eval/%s" % ev["id"])
        break
else:
    print("  no eval page listed (the API only returns the ~20 newest evals)")
' "$rev"
}

case ${1:-} in
list)
  shift
  cmd_list "$@"
  ;;
check)
  shift
  cmd_check "$@"
  ;;
versions)
  shift
  cmd_versions "$@"
  ;;
pin)
  shift
  cmd_pin "$@"
  ;;
diff)
  shift
  cmd_diff "$@"
  ;;
pick)
  shift
  cmd_pick "$@"
  ;;
hydra)
  shift
  cmd_hydra "$@"
  ;;
-h | --help | "")
  usage
  ;;
*) die "unknown command ${1}" ;;
esac
