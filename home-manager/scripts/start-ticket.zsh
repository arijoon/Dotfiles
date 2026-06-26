# start-ticket — create a Jira ticket, branch with worktrunk, title the kitty tab.
#
# Defined as a zsh *function* (not a writeShellApplication binary) on purpose:
# `wt switch` cd's the calling shell via worktrunk's shell wrapper, so this has
# to run *in* the interactive shell to actually land you inside the new
# worktree. `jira` and `kitty` are taken from $PATH — `jira` is intentionally
# NOT managed by nix here.
#
# Usage:
#   start-ticket -s "summary" [-b "description"] [options]
#   start-ticket --ticket BINF-1274 -B dlq-alerts [options]   # skip creation
#
# Options:
#   -s, --summary  TEXT   Jira summary (required unless --ticket is given)
#   -b, --body     TEXT   Jira description (default: the summary)
#   -t, --type     TYPE   Jira issue type: Task | Bug (default: Task)
#   -p, --project  KEY    Jira project key (default: BINF)
#       --ticket   KEY    Existing ticket id (e.g. BINF-1274); skips creation
#       --base     REF    Base branch for the worktree (default: origin/dev)
#   -B, --branch   SLUG   Branch suffix after "KEY/" (default: slug of summary)
#   -k, --kitty    TEXT   Kitty tab title (default: "KEY suffix")
#   -h, --help            Show this help
#
# Examples:
#   start-ticket -s "stream lag alerts for blocked processors" \
#                -b "Alert if stream processors are blocked"
#   start-ticket --ticket BINF-1274 -B dlq-alerts-stats --base origin/main

_start-ticket-usage() {
  print -r -- 'start-ticket — create a Jira ticket, branch with worktrunk, title the kitty tab.

Usage:
  start-ticket -s "summary" [-b "description"] [options]
  start-ticket --ticket BINF-1274 -B dlq-alerts [options]   # skip creation

Options:
  -s, --summary  TEXT   Jira summary (required unless --ticket is given)
  -b, --body     TEXT   Jira description (default: the summary)
  -t, --type     TYPE   Jira issue type: Task | Bug (default: Task)
  -p, --project  KEY    Jira project key (default: BINF)
      --ticket   KEY    Existing ticket id (e.g. BINF-1274); skips creation
      --base     REF    Base branch for the worktree (default: origin/dev)
  -B, --branch   SLUG   Branch suffix after "KEY/" (default: slug of summary)
  -k, --kitty    TEXT   Kitty tab title (default: "KEY suffix")
  -h, --help            Show this help'
}

start-ticket() {
  emulate -L zsh
  setopt local_options pipe_fail

  local summary="" body="" type="Task" project="BINF" ticket="" \
        base="origin/dev" suffix="" kitty_title=""

  while (( $# )); do
    case "$1" in
      -s|--summary) summary="$2";     shift 2 ;;
      -b|--body)    body="$2";        shift 2 ;;
      -t|--type)    type="$2";        shift 2 ;;
      -p|--project) project="$2";     shift 2 ;;
      --ticket)     ticket="$2";      shift 2 ;;
      --base)       base="$2";        shift 2 ;;
      -B|--branch)  suffix="$2";      shift 2 ;;
      -k|--kitty)   kitty_title="$2"; shift 2 ;;
      -h|--help)    _start-ticket-usage; return 0 ;;
      *) print -u2 "start-ticket: unknown argument: $1 (try --help)"; return 2 ;;
    esac
  done

  # slugify: lowercase, non-alphanumerics -> single dash, trim leading/trailing.
  local _slug() { print -r -- "${(L)1}" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }

  # 1. Create the Jira ticket (unless an id was supplied).
  if [[ -z "$ticket" ]]; then
    if [[ -z "$summary" ]]; then
      print -u2 "start-ticket: --summary is required when --ticket is not given"
      return 2
    fi
    : "${body:=$summary}"

    if ! command -v jira >/dev/null 2>&1; then
      print -u2 "start-ticket: 'jira' not found on PATH"
      return 1
    fi

    local out
    out="$(jira issue create -p "$project" -t "$type" -s "$summary" -b "$body" --no-input 2>&1)" \
      || { print -u2 "$out"; return 1; }
    print -r -- "$out"

    ticket="$(print -r -- "$out" | grep -oiE "${project}-[0-9]+" | head -1)"
    if [[ -z "$ticket" ]]; then
      print -u2 "start-ticket: could not parse a ticket id from jira output"
      return 1
    fi
    print -r -- "start-ticket: created $ticket"
  fi

  # 2. Derive the branch and switch to a new worktree.
  if [[ -z "$suffix" ]]; then
    if [[ -z "$summary" ]]; then
      print -u2 "start-ticket: need --branch (suffix) when reusing a ticket without --summary"
      return 2
    fi
    suffix="$(_slug "$summary")"
  else
    suffix="$(_slug "$suffix")"
  fi

  local branch="${ticket}/${suffix}"
  print -r -- "start-ticket: wt switch --create $branch --base $base"
  wt switch --create "$branch" --base "$base" || return $?

  # 3. Title the kitty tab (same effect as Ctrl+Shift+, -> set_tab_title).
  : "${kitty_title:=${ticket} ${suffix}}"
  if [[ -n "$KITTY_WINDOW_ID" ]] && command -v kitty >/dev/null 2>&1; then
    kitty @ set-tab-title "$kitty_title" \
      || print -u2 "start-ticket: could not set kitty tab title"
  fi
}
