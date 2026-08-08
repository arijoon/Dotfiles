{ pkgs }:
let
  coreutils = "${pkgs.coreutils}/bin";
  findutils = "${pkgs.findutils}/bin";
  tar = "${pkgs.gnutar}/bin/tar";
  gzip = "${pkgs.gzip}/bin/gzip";
in
pkgs.writeShellApplication {
  name = "backup-if-changed";
  text = ''
    usage() {
      echo "usage: backup-if-changed [--limit N] <source-dir> <dest-dir>" >&2
      exit 2
    }

    LIMIT=20
    positional=()

    while [ "$#" -gt 0 ]; do
      case "$1" in
      --limit)
        [ "$#" -ge 2 ] || usage
        LIMIT="$2"
        shift 2
        ;;
      --limit=*)
        LIMIT="''${1#*=}"
        shift
        ;;
      -h | --help)
        usage
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        echo "backup-if-changed: unknown option: $1" >&2
        usage
        ;;
      *)
        positional+=("$1")
        shift
        ;;
      esac
    done

    [ "''${#positional[@]}" -eq 2 ] || usage

    SRC="''${positional[0]%/}"
    DEST="''${positional[1]%/}"

    case "$LIMIT" in
    "" | *[!0-9]*)
      echo "backup-if-changed: --limit must be a positive integer: $LIMIT" >&2
      exit 2
      ;;
    esac

    if [ "$LIMIT" -lt 1 ]; then
      echo "backup-if-changed: --limit must be at least 1" >&2
      exit 2
    fi

    if [ ! -d "$SRC" ]; then
      echo "backup-if-changed: source not found: $SRC" >&2
      exit 1
    fi

    parent=$(${coreutils}/dirname "$DEST")

    if [ ! -d "$parent" ]; then
      echo "backup-if-changed: dest parent not found (drive not mounted?): $parent" >&2
      exit 1
    fi

    ${coreutils}/mkdir -p "$DEST"

    name=$(${coreutils}/basename "$SRC")
    state="$DEST/.$name.last-hash"
    hash=$(${findutils}/find "$SRC" -type f -print0 |
      ${coreutils}/sort -z |
      ${findutils}/xargs -0 -r ${coreutils}/sha256sum |
      ${coreutils}/sha256sum |
      ${coreutils}/cut -d' ' -f1)

    if [ -f "$state" ] && [ "$(${coreutils}/cat "$state")" = "$hash" ]; then
      exit 0
    fi

    stamp=$(${coreutils}/date +%Y%m%d-%H%M%S)
    archive="$DEST/$name-$stamp.tar.gz"
    n=0
    while [ -e "$archive" ]; do
      n=$((n + 1))
      archive="$DEST/$name-$stamp.$n.tar.gz"
    done
    trap '${coreutils}/rm -f "$archive.tmp"' EXIT

    ${tar} --use-compress-program=${gzip} -cf "$archive.tmp" -C "$(${coreutils}/dirname "$SRC")" "$name"
    ${coreutils}/mv "$archive.tmp" "$archive"
    printf '%s\n' "$hash" >"$state"

    echo "backup-if-changed: wrote $archive"

    ${findutils}/find "$DEST" -maxdepth 1 -name "$name-*.tar.gz" -printf '%T@ %p\0' |
      ${coreutils}/sort -zrn |
      ${coreutils}/tail -zn "+$((LIMIT + 1))" |
      ${coreutils}/cut -z -d' ' -f2- |
      ${findutils}/xargs -0 -r ${coreutils}/rm -f --
  '';
}
