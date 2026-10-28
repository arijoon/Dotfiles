usage() {
  echo "Usage: nix-project-init [--name NAME] [--no-nix] [DIR]" >&2
}

name=""
run_nix=1
dir="."
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) name="$2"; shift 2 ;;
    --no-nix) run_nix=0; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) usage; exit 1 ;;
    *) dir="$1"; shift ;;
  esac
done

mkdir -p "$dir"
cd "$dir" || exit 1
git rev-parse --show-toplevel >/dev/null 2>&1 || git init -q
cd "$(git rev-parse --show-toplevel)" || exit 1
root="$PWD"
[ -n "$name" ] || name="$(basename "$root")"

created=()
kept=()
staged=(.gitignore)

place() {
  local src="$NIX_PROJECT_TEMPLATES/$1" dest="$2"
  if [ -e "$dest" ]; then
    kept+=("$dest  (template: $src)")
    return
  fi
  mkdir -p "$(dirname "$dest")"
  sed "s|@PROJECT@|$name|g" "$src" >"$dest"
  chmod 644 "$dest"
  created+=("$dest")
  staged+=("$dest")
}

place flake.nix flake.nix
while IFS= read -r -d "" file; do
  place "${file#"$NIX_PROJECT_TEMPLATES"/}" "${file#"$NIX_PROJECT_TEMPLATES"/}"
done < <(find "$NIX_PROJECT_TEMPLATES/nix" -type f -print0)
place envrc .envrc
place prettierrc .prettierrc
place treefmt.toml treefmt.toml
place CLAUDE.project.md CLAUDE.md
place claude-skills/local-dev/SKILL.md .claude/skills/local-dev/SKILL.md

touch .gitignore
added=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  grep -qxF -- "$line" .gitignore || { printf '%s\n' "$line" >>.gitignore; added=1; }
done <"$NIX_PROJECT_TEMPLATES/gitignore"
[ "$added" -eq 0 ] || created+=(".gitignore (entries appended)")

if [ ! -e .secrets/dev.key ]; then
  (umask 077 && mkdir -p .secrets && age-keygen -o .secrets/dev.key 2>/dev/null)
  created+=(".secrets/dev.key")
fi
recipient="$(age-keygen -y .secrets/dev.key)"
if grep -qF @DEV_RECIPIENT@ nix/envs/dev/default.nix; then
  sed -i "s|@DEV_RECIPIENT@|$recipient|" nix/envs/dev/default.nix
fi

git add -- "${staged[@]}"

if [ "$run_nix" -eq 1 ]; then
  if nix run .#p.dev.tasks.sops-config; then
    git add -- .sops.yaml flake.lock
  else
    echo "nix-project-init: sops-config failed; fix the error, then: nix run .#p.dev.tasks.sops-config" >&2
  fi
fi

echo
echo "nix-project-init: $root ($name)"
[ "${#created[@]}" -eq 0 ] || printf '  created  %s\n' "${created[@]}"
[ "${#kept[@]}" -eq 0 ] || printf '  kept     %s\n' "${kept[@]}"
echo "  dev age recipient: $recipient"
echo "  back up .secrets/dev.key off this machine; nothing was committed"
