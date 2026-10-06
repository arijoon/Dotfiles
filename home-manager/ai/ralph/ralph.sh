shopt -s nullglob inherit_errexit
shopt -u patsub_replacement 2>/dev/null || true

share="${RALPH_SHARE:?RALPH_SHARE must name the directory holding the default prompts}"
user_path="${ralph_user_path:-$PATH}"
tab=$'\t'

usage() {
  cat <<'USAGE'
Usage: ralph [options]

Works through a repository's task files. Each task gets its own git worktree
and branch, a sandboxed `claude -p` does it, the gate must pass, and the branch
is fast-forwarded into the target branch.

  (no option)      work through ready tasks until none are left
  -j, --jobs N     work on up to N tasks at the same time
  --once           start at most one task
  --task ID        run this ready task, then stop
  --resume ID      continue a failed or blocked task in its kept worktree, then go on
  --discard ID     delete a task's kept worktree, branch and state
  --status         list every task with its status and any kept state
  --dry-run        show the next ready task, how it would run, and its prompt
  --reviews        print the last run's reviews of sensitive branches again
  --config         print the effective configuration
  --keep-going     keep starting tasks after one fails or blocks
  --in-sandbox     iterations share the sandbox this loop already runs in
                   (detected automatically: `ls /` is denied under landrun)
  -h, --help       show this help

Configuration is read from .ralph/config.json in the main checkout, or from the
file named by RALPH_CONFIG. RALPH_TARGET, RALPH_MODEL, RALPH_TIMEOUT,
RALPH_RETRIES, RALPH_JOBS, RALPH_MAX_TASKS and RALPH_SANDBOX override it for
one run.
USAGE
}

die() {
  echo "ralph: $*" >&2
  exit 1
}

say() {
  echo "ralph: $*" >&2
}

g() {
  git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c commit.gpgSign=false "$@"
}

export GIT_PAGER=cat GIT_TERMINAL_PROMPT=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_EXTERNAL_DIFF

mode=loop
chosen=""
jobs_flag=""
keep_going_flag=""
in_sandbox_flag=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --once) mode=once ;;
    --task | --resume | --discard)
      mode="${1#--}"
      chosen="${2:-}"
      [ -n "$chosen" ] || die "$1 needs a task id"
      shift
      ;;
    -j | --jobs)
      jobs_flag="${2:-}"
      [ -n "$jobs_flag" ] || die "$1 needs a number"
      shift
      ;;
    --jobs=*) jobs_flag="${1#*=}" ;;
    --status | --dry-run | --reviews | --config) mode="${1#--}" ;;
    --keep-going) keep_going_flag=true ;;
    --in-sandbox) in_sandbox_flag=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

root="$(g worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
[ -n "$root" ] || die "run ralph inside a git repository"
[ "$(g -C "$root" rev-parse --is-bare-repository)" = false ] || die "bare repositories are not supported"
common="$(g -C "$root" rev-parse --path-format=absolute --git-common-dir)"

abs_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    \~) printf '%s\n' "$HOME" ;;
    \~/*) printf '%s\n' "$HOME/${1#\~/}" ;;
    *) printf '%s\n' "$root/$1" ;;
  esac
}

rel() {
  printf '%s\n' "${1#"$root"/}"
}

config_file="${RALPH_CONFIG:-$root/.ralph/config.json}"
config='{}'
if [ -f "$config_file" ]; then
  config="$(jq -ce 'if type == "object" then . else error("not an object") end' "$config_file")" ||
    die "$config_file is not a JSON object"
elif [ -n "${RALPH_CONFIG:-}" ]; then
  die "RALPH_CONFIG names $RALPH_CONFIG, which does not exist"
fi

conf() {
  jq -r --arg p "$1" --arg d "${2-}" '
    getpath($p | split(".")) as $v
    | if $v == null then $d
      elif ($v | type) == "string" then $v
      elif ($v | type) == "number" or ($v | type) == "boolean" then $v | tostring
      else error("\($p) must be a string, a number or a boolean") end
  ' <<<"$config" || die "bad value for $1 in $config_file"
}

conf_list() {
  local p="$1"
  shift
  if jq -e --arg p "$p" 'getpath($p | split(".")) != null' <<<"$config" >/dev/null; then
    jq -r --arg p "$p" '
      getpath($p | split("."))
      | if type == "array" then .[] | tostring
        elif type == "string" then .
        else error("\($p) must be a list of strings") end
    ' <<<"$config" || die "bad value for $p in $config_file"
  elif [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
  fi
}

conf_map() {
  jq -r --arg p "$1" '
    (getpath($p | split(".")) // {})
    | if type == "object" then to_entries[] | "\(.key)=\(.value | tostring)"
      else error("\($p) must be an object") end
  ' <<<"$config" || die "bad value for $1 in $config_file"
}

lines=()

to_lines() {
  lines=()
  [ -z "$1" ] || mapfile -t lines <<<"$1"
}

target="${RALPH_TARGET:-$(conf target)}"
if [ -z "$target" ]; then
  target="$(g -C "$root" symbolic-ref --quiet --short HEAD)" ||
    die "the main checkout is on no branch; set target in $config_file"
fi
g -C "$root" rev-parse --verify --quiet "refs/heads/$target" >/dev/null || die "there is no branch $target"

tasks_dir="$(conf tasksDir docs/tasks)"
tasks_dir="${tasks_dir%/}"
decisions_dir="$(conf decisionsDir docs/decisions)"
decisions_dir="${decisions_dir%/}"
worktree_dir="$(abs_path "$(conf worktreeDir .tmp/worktrees)")"
state_dir="$(abs_path "$(conf stateDir .tmp/ralph)")"
branch_prefix="$(conf branchPrefix ralph/)"
gate="$(conf gate)"
setup_cmd="$(conf setup)"
after_merge="$(conf afterMerge)"
services_wrap="$(conf services.wrap)"
svc_start_timeout="$(conf services.startTimeout 600)"
task_timeout="${RALPH_TIMEOUT:-$(conf timeout 90m)}"
retries="${RALPH_RETRIES:-$(conf retries 1)}"
jobs="${jobs_flag:-${RALPH_JOBS:-$(conf jobs 1)}}"
max_tasks="${RALPH_MAX_TASKS:-$(conf maxTasks 0)}"
model="${RALPH_MODEL:-$(conf model)}"
keep_going="${keep_going_flag:-$(conf keepGoing false)}"
sandbox_mode="${RALPH_SANDBOX:-$(conf sandbox.mode auto)}"
read -r -a claude_cmd <<<"$(conf claude claude)"
read -r -a sandbox_cmd <<<"$(conf sandbox.command sandbox-ai)"
text="$(conf_list services.env)"
to_lines "$text"
svc_keys=("${lines[@]}")
text="$(conf_list agentArgs)"
to_lines "$text"
agent_args=("${lines[@]}")
text="$(conf_list unsetEnv)"
to_lines "$text"
unset_env=("${lines[@]}")
text="$(conf_list sandbox.rw "$HOME/.cache/nix")"
to_lines "$text"
sandbox_rw=("${lines[@]}")
text="$(conf_list sandbox.ro)"
to_lines "$text"
sandbox_ro=("${lines[@]}")
text="$(conf_list sandbox.rox)"
to_lines "$text"
sandbox_rox=("${lines[@]}")
text="$(conf_list sensitivePaths .ralph/ .claude/ .mcp.json .envrc .github/ .config/wt.toml)"
to_lines "$text"
sensitive=("${lines[@]}")
text="$(conf_map env)"
to_lines "$text"
config_env=("${lines[@]}")

for pair in "retries=$retries" "jobs=$jobs" "maxTasks=$max_tasks" "services.startTimeout=$svc_start_timeout"; do
  [[ ${pair#*=} =~ ^[0-9]+$ ]] || die "${pair%%=*} must be a whole number, not '${pair#*=}'"
done
[ "$jobs" -ge 1 ] || die "jobs must be at least 1"
[[ $task_timeout =~ ^[0-9]+(\.[0-9]+)?[smhd]?$ ]] || die "timeout must look like 90m, not '$task_timeout'"
case "$keep_going" in
  true | false) ;;
  *) die "keepGoing must be true or false" ;;
esac
[ "${#claude_cmd[@]}" -gt 0 ] || die "claude must name a command"

if [ "$in_sandbox_flag" -eq 1 ]; then
  sandbox_mode=inherit
fi
sandboxed_now() {
  ! ls / >/dev/null 2>&1
}
case "$sandbox_mode" in
  auto)
    if sandboxed_now; then
      sandbox_mode=inherit
    else
      sandbox_mode=wrap
    fi
    ;;
  wrap | inherit | none) ;;
  *) die "sandbox.mode must be auto, wrap, inherit or none, not '$sandbox_mode'" ;;
esac

settings="$(
  case "$(jq -r '.settings | type' <<<"$config")" in
    null) jq -c . "$share/settings.json" ;;
    object) jq -c .settings <<<"$config" ;;
    string)
      file="$(abs_path "$(conf settings)")"
      [ -f "$file" ] || die "settings names $file, which does not exist"
      jq -c . "$file"
      ;;
    *) die "settings must be an object or the path of a JSON file" ;;
  esac
)"

template() {
  local value
  value="$(conf "$1")"
  if [ -n "$value" ]; then
    value="$(abs_path "$value")"
    [ -f "$value" ] || die "$1 names $value, which does not exist"
    printf '%s\n' "$value"
  elif [ -f "$2" ]; then
    printf '%s\n' "$2"
  fi
}

prompt_file="$(template prompt "$share/PROMPT.md")"
review_file="$(template reviewPrompt "$share/REVIEW.md")"
instructions_file="$(template instructions "$root/.ralph/instructions.md")"
review_instructions_file="$(template reviewInstructions "$root/.ralph/review.md")"

unset_args=()
for key in "${unset_env[@]}"; do
  unset_args+=(-u "$key")
done

locks="$state_dir/locks"
runs="$state_dir/runs"
run_id=""
run_dir=""

task_dir() {
  printf '%s/tasks/%s\n' "$state_dir" "$1"
}

state_file() {
  printf '%s/state.json\n' "$(task_dir "$1")"
}

tasks_tsv=""

load_tasks() {
  local tmp dupes
  local -a files
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/ralph-tasks.XXXXXX")"
  if g -C "$root" cat-file -e "$target:$tasks_dir" 2>/dev/null; then
    g -C "$root" archive --format=tar "$target" -- "$tasks_dir" | tar -x -C "$tmp"
  fi
  files=("$tmp/$tasks_dir"/*-*.md)
  if [ "${#files[@]}" -gt 0 ]; then
    awk '
      function flush() {
        if (base != "") print id "\t" st "\t" dep "\t" title "\t" base
      }
      FNR == 1 {
        flush()
        base = FILENAME
        sub(/.*\//, "", base)
        id = base
        sub(/-.*/, "", id)
        st = ""
        dep = ""
        title = ""
        body = ($0 != "---")
        next
      }
      body { next }
      $0 == "---" { body = 1; next }
      {
        i = index($0, ":")
        if (i == 0) next
        k = substr($0, 1, i - 1)
        v = substr($0, i + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", v)
        gsub(/\t/, " ", v)
        if (k == "status") st = v
        else if (k == "depends") dep = v
        else if (k == "title") title = v
      }
      END { flush() }
    ' "${files[@]}" | sort -t "$tab" -k1,1V
  fi
  rm -rf "$tmp"
}

refresh_tasks() {
  local dupes
  tasks_tsv="$(load_tasks)"
  dupes="$(cut -f1 <<<"$tasks_tsv" | sort | uniq -d | paste -sd ' ')"
  [ -z "$dupes" ] || die "more than one task file in $tasks_dir on $target has the id $dupes"
}

task_field() {
  awk -F '\t' -v id="$1" -v col="$2" '$1 == id { print $col; exit }' <<<"$tasks_tsv"
}

ready_ids() {
  awk -F '\t' '
    $1 != "" { status[$1] = $2; ids[++n] = $1; deps[n] = $3 }
    END {
      for (i = 1; i <= n; i++) {
        if (status[ids[i]] != "todo") continue
        m = split(deps[i], d, /[ ,\[\]]+/)
        ok = 1
        for (j = 1; j <= m; j++) if (d[j] != "" && d[j] != "-" && status[d[j]] != "done") ok = 0
        if (ok) print ids[i]
      }
    }
  ' <<<"$tasks_tsv"
}

waiting_on() {
  awk -F '\t' -v id="$1" '
    $1 != "" { status[$1] = $2; deps[$1] = $3 }
    END {
      m = split(deps[id], d, /[ ,\[\]]+/)
      out = ""
      for (j = 1; j <= m; j++) {
        if (d[j] == "" || d[j] == "-" || status[d[j]] == "done") continue
        out = out (out == "" ? "" : " ") d[j] (d[j] in status ? "" : " (missing)")
      }
      print out
    }
  ' <<<"$tasks_tsv"
}

field() {
  awk -v key="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 {
      i = index($0, ":")
      if (i > 0 && substr($0, 1, i - 1) == key) {
        v = substr($0, i + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", v)
        print v
        exit
      }
    }
  ' "$1"
}

section() {
  awk -v heading="## $2" '
    $0 == heading { on = 1; next }
    on && /^## / { exit }
    on { print }
  ' "$1"
}

t_id=""
t_file=""
t_title=""
t_branch=""
t_wt=""
t_dir=""
t_rel=""
task_env=()

use_task() {
  local kv
  t_id="$1"
  t_file="$(task_field "$1" 5)"
  [ -n "$t_file" ] || die "there is no task $1 in $tasks_dir on $target"
  t_title="$(task_field "$1" 4)"
  t_branch="$branch_prefix${t_file%.md}"
  t_wt="$worktree_dir/${t_branch//\//-}"
  t_dir="$(task_dir "$1")"
  t_rel="$tasks_dir/$t_file"
  task_env=(
    GIT_CONFIG_COUNT=1
    GIT_CONFIG_KEY_0=commit.gpgSign
    GIT_CONFIG_VALUE_0=false
    "RALPH_TASK_ID=$t_id"
    "RALPH_BRANCH=$t_branch"
    "RALPH_TARGET=$target"
    "RALPH_WORKTREE=$t_wt"
    "RALPH_ROOT=$root"
  )
  for kv in "${config_env[@]}"; do
    kv="${kv//\{\{TASK_ID\}\}/$t_id}"
    kv="${kv//\{\{BRANCH\}\}/$t_branch}"
    kv="${kv//\{\{WORKTREE\}\}/$t_wt}"
    kv="${kv//\{\{ROOT\}\}/$root}"
    task_env+=("$kv")
  done
}

task_fd=""
merge_fd=""
pick_fd=""

lock_task() {
  local fd
  mkdir -p "$locks"
  exec {fd}>>"$locks/$1.lock"
  if flock -n "$fd"; then
    task_fd="$fd"
    return 0
  fi
  exec {fd}>&-
  return 1
}

unlock_task() {
  if [ -n "$task_fd" ]; then
    exec {task_fd}>&-
    task_fd=""
  fi
}

is_running() {
  local fd status=1
  [ -e "$locks/$1.lock" ] || return 1
  exec {fd}>>"$locks/$1.lock"
  flock -n "$fd" || status=0
  exec {fd}>&-
  return "$status"
}

lock_merge() {
  mkdir -p "$locks"
  exec {merge_fd}>>"$locks/merge.lock"
  flock "$merge_fd"
}

unlock_merge() {
  if [ -n "$merge_fd" ]; then
    exec {merge_fd}>&-
    merge_fd=""
  fi
}

lock_pick() {
  mkdir -p "$locks"
  exec {pick_fd}>>"$locks/pick.lock"
  flock "$pick_fd"
}

unlock_pick() {
  if [ -n "$pick_fd" ]; then
    exec {pick_fd}>&-
    pick_fd=""
  fi
}

write_state() {
  mkdir -p "$t_dir"
  jq -n \
    --arg id "$t_id" \
    --arg status "$1" \
    --arg reason "$2" \
    --arg attempts "$3" \
    --arg branch "$t_branch" \
    --arg worktree "$t_wt" \
    --arg run "$run_id" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{id: $id, status: $status, reason: $reason, attempts: ($attempts | tonumber), branch: $branch, worktree: $worktree, run: $run, at: $at}' \
    >"$(state_file "$t_id").tmp"
  mv "$(state_file "$t_id").tmp" "$(state_file "$t_id")"
}

outcome() {
  printf '%s\n%s\n' "$1" "${2:-}" >"$run_dir/outcomes/$t_id"
}

stop_run() {
  : >"$run_dir/stop"
}

log_path() {
  mkdir -p "$t_dir"
  printf '%s/%s.%s.%s\n' "$t_dir" "$run_id" "$1" "$2"
}

hash_of() {
  if [ -L "$1" ]; then
    printf 'symlink:%s\n' "$(readlink "$1")"
  elif [ -f "$1" ]; then
    sha256sum <"$1" | cut -c1-64
  else
    echo directory
  fi
}

fingerprint() {
  local f
  for f in "$common/config" "$common/config.worktree" "$common/info/attributes" "$common"/worktrees/*/config.worktree; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    printf '%s  %s\n' "$(hash_of "$f")" "${f#"$common"/}"
  done
  if [ -d "$common/hooks" ]; then
    find "$common/hooks" -mindepth 1 -print0 | sort -z | while IFS= read -r -d '' f; do
      printf '%s  %s\n' "$(hash_of "$f")" "${f#"$common"/}"
    done
  fi
}

fingerprint_changes() {
  awk '
    FNR == NR { before[$2] = $1; next }
    { after[$2] = $1 }
    END {
      for (p in after) {
        if (!(p in before)) print "added: .git/" p
        else if (before[p] != after[p]) print "changed: .git/" p
      }
      for (p in before) if (!(p in after)) print "removed: .git/" p
    }
  ' "$run_dir/fingerprint" <(fingerprint) | sort
}

fatal=""
failure=""
blocked=""

guard() {
  local changes
  changes="$(fingerprint_changes)"
  [ -n "$changes" ] || return 0
  fatal="the git config or hooks changed $1: $(head -n 1 <<<"$changes")"
  say "task $t_id: the repository's git config or hooks changed $1, so code could run outside the sandbox:"
  to_lines "$changes"
  printf '  %s\n' "${lines[@]}" >&2
  say "task $t_id: stopping without merging; the worktree is kept at $t_wt. Undo the change, then 'ralph --resume $t_id' or 'ralph --discard $t_id'"
  return 1
}

services_note() {
  local keys
  if [ -z "$services_wrap" ]; then
    echo "The loop starts no services for this attempt."
    return 0
  fi
  keys="$(printf '`%s`, ' "${svc_keys[@]}")"
  keys="${keys%, }"
  echo "This attempt has services of its own, started by the loop with \`$services_wrap\` and torn down when the attempt ends. They are reached through ${keys:-the environment}. Never start, stop or reset them. If you need another instance, run your command under \`$services_wrap\` yourself."
}

fill() {
  local text="$1"
  text="${text//\{\{TASK_ID\}\}/$t_id}"
  text="${text//\{\{TASK_TITLE\}\}/$t_title}"
  text="${text//\{\{TASK_FILE\}\}/$t_rel}"
  text="${text//\{\{TASKS_DIR\}\}/$tasks_dir}"
  text="${text//\{\{DECISIONS_DIR\}\}/$decisions_dir}"
  text="${text//\{\{BRANCH\}\}/$t_branch}"
  text="${text//\{\{TARGET\}\}/$target}"
  text="${text//\{\{TIMEOUT\}\}/$task_timeout}"
  text="${text//\{\{GATE\}\}/$gate}"
  text="${text//\{\{SERVICES\}\}/$(services_note)}"
  printf '%s\n' "$text"
}

place() {
  local text="$1" key="$2" value="$3" heading="$4"
  if [ -n "$value" ] && [ -n "$heading" ]; then
    value="## $heading"$'\n\n'"$value"
  fi
  if [[ $text == *"{{$key}}"* ]]; then
    text="${text//\{\{$key\}\}/$value}"
  elif [ -n "$value" ]; then
    text="$text"$'\n\n'"$value"
  fi
  printf '%s\n' "$text"
}

instructions_of() {
  [ -n "$1" ] || return 0
  fill "$(cat "$1")"
}

render_prompt() {
  local attempt="$1" context="$2" text
  text="$(fill "$(cat "$prompt_file")")"
  text="${text//\{\{ATTEMPT\}\}/$attempt}"
  text="$(place "$text" INSTRUCTIONS "$(instructions_of "$instructions_file")" "Project instructions")"
  text="$(place "$text" CONTEXT "${context:-This is the first attempt at this task.}" "")"
  cat -s <<<"$text"
}

render_review() {
  local base="$1" head="$2" touched="$3" text paths
  to_lines "$touched"
  paths="$(printf -- '- `%s`\n' "${lines[@]}")"
  text="$(fill "$(cat "$review_file")")"
  text="${text//\{\{BASE\}\}/$base}"
  text="${text//\{\{HEAD\}\}/$head}"
  text="$(place "$text" INSTRUCTIONS "$(instructions_of "$review_instructions_file")" "Project instructions")"
  text="$(place "$text" PATHS "$paths" "")"
  cat -s <<<"$text"
}

sandbox_args=()

build_sandbox_args() {
  local p
  sandbox_args=()
  [ "$sandbox_mode" = wrap ] || return 0
  sandbox_args=(--rw "$common")
  for p in "${sandbox_rw[@]}"; do
    p="$(abs_path "$p")"
    [ ! -e "$p" ] || sandbox_args+=(--rw "$p")
  done
  for p in "${sandbox_rox[@]}"; do
    p="$(abs_path "$p")"
    [ ! -e "$p" ] || sandbox_args+=(--rox "$p")
  done
  for p in "${sandbox_ro[@]}"; do
    p="$(abs_path "$p")"
    [ ! -e "$p" ] || sandbox_args+=(--ro "$(cd "$p" 2>/dev/null && pwd || echo "$p")")
  done
}

svc_env=()
svc_pid=""

start_services() {
  local log="$1" line ready=0 out
  svc_env=()
  [ -n "$services_wrap" ] || return 0
  coproc SVC {
    [ -z "$task_fd" ] || exec {task_fd}>&-
    cd "$t_wt" || exit 1
    exec env --default-signal=INT "${unset_args[@]}" PATH="$user_path" "${task_env[@]}" "$BASH" -c "$services_wrap"' "$@"' ralph-services \
      "$BASH" -c 'for k in "$@"; do [ -z "${!k+x}" ] || printf "ralph-env:%s=%s\n" "$k" "${!k}"; done; echo ralph-ready; read -r _ || true' \
      ralph-hold "${svc_keys[@]}"
  } 2>"$log"
  svc_pid="$!"
  out="${SVC[0]}"
  while IFS= read -r -t "$svc_start_timeout" line <&"$out"; do
    case "$line" in
      ralph-ready)
        ready=1
        break
        ;;
      ralph-env:*) svc_env+=("${line#ralph-env:}") ;;
    esac
  done
  if [ "$ready" -eq 0 ]; then
    stop_services
    return 1
  fi
}

stop_services() {
  local fd i
  [ -n "$svc_pid" ] || return 0
  fd="${SVC[1]:-}"
  if [ -n "$fd" ]; then
    { exec {fd}>&-; } 2>/dev/null || true
  fi
  for ((i = 0; i < 300; i++)); do
    kill -0 "$svc_pid" 2>/dev/null || break
    sleep 0.1
  done
  kill -TERM "$svc_pid" 2>/dev/null || true
  wait "$svc_pid" 2>/dev/null || true
  svc_pid=""
  svc_env=()
}

child=""

run_in() {
  local out="$1" sandboxed="$2" input="$3" status=0 kv
  shift 3
  local -a cmd=("$@") envs=("${task_env[@]}" "${svc_env[@]}") forward=()
  if [ "$sandboxed" = 1 ] && [ "$sandbox_mode" = wrap ]; then
    for kv in "${envs[@]}"; do
      forward+=(--env "${kv%%=*}")
    done
    cmd=("${sandbox_cmd[@]}" -l "${sandbox_args[@]}" "${forward[@]}" -- "${cmd[@]}")
  fi
  (
    [ -z "$task_fd" ] || exec {task_fd}>&-
    [ -z "$merge_fd" ] || exec {merge_fd}>&-
    cd "$t_wt" || exit 1
    exec env --default-signal=INT "${unset_args[@]}" PATH="$user_path" "${envs[@]}" "$timeout_bin" --kill-after=2m "$task_timeout" "${cmd[@]}"
  ) <"$input" >"$out" 2>&1 &
  child=$!
  wait "$child" || status=$?
  child=""
  return "$status"
}

run_hook() {
  local script="$1" dir="$2" log="$3" status=0
  shift 3
  (
    [ -z "$task_fd" ] || exec {task_fd}>&-
    [ -z "$merge_fd" ] || exec {merge_fd}>&-
    cd "$dir" || exit 1
    exec env --default-signal=INT "${unset_args[@]}" PATH="$user_path" "${task_env[@]}" "$@" "$timeout_bin" --kill-after=1m "$task_timeout" "$BASH" -c "$script"
  ) </dev/null >>"$log" 2>&1 &
  child=$!
  wait "$child" || status=$?
  child=""
  return "$status"
}

agent_cmd=()

build_agent_cmd() {
  agent_cmd=("${claude_cmd[@]}" -p
    --dangerously-skip-permissions
    --settings "$settings"
    --output-format stream-json
    --verbose)
  if [ -n "$model" ]; then
    agent_cmd+=(--model "$model")
  fi
  agent_cmd+=("${agent_args[@]}")
}

agent_summary() {
  jq -Rr 'fromjson? | select(.type == "result") | .result // empty' "$1" 2>/dev/null | tail -n 40 || true
}

limit_reason() {
  case "$2" in
    124 | 137) echo "$1 hit the $task_timeout limit" ;;
    *) echo "$1 exited with status $2" ;;
  esac
}

run_gate() {
  local attempt="$1" label="$2" log status=0
  log="$(log_path "$attempt" "$label.log")"
  say "task $t_id attempt $attempt: $label running (log $(rel "$log"))"
  run_in "$log" 1 /dev/null "$BASH" -c "$gate" || status=$?
  [ "$status" -ne 0 ] || return 0
  failure="$(limit_reason "the gate (\`$gate\`)" "$status"). The end of its output:
$(tail -n 150 "$log")"
  return 1
}

review_branch() {
  local attempt="$1" base head touched report log prompt status=0 result reason="" note=""
  [ "${#sensitive[@]}" -gt 0 ] || return 0
  base="$(g -C "$t_wt" merge-base HEAD "$target")"
  head="$(g -C "$t_wt" rev-parse HEAD)"
  touched="$(g -C "$t_wt" diff --no-ext-diff --no-renames --name-only "$base" "$head" -- "${sensitive[@]}")"
  [ -n "$touched" ] || return 0

  report="$t_dir/review.md"
  log="$(log_path "$attempt" review.jsonl)"
  prompt="$(log_path "$attempt" review-prompt.md)"
  say "task $t_id: the branch touches $(paste -sd ' ' <<<"$touched"); reviewing it (log $(rel "$log"))"
  render_review "$base" "$head" "$touched" >"$prompt"
  build_agent_cmd
  run_in "$log" 1 "$prompt" "${agent_cmd[@]}" || status=$?
  result="$(jq -Rr 'fromjson? | select(.type == "result" and (.is_error | not)) | .result // empty' "$log" 2>/dev/null || true)"
  if [ "$status" -ne 0 ]; then
    reason="$(limit_reason "the review" "$status")"
  elif [ -z "$result" ]; then
    reason="the review ended without a report"
  fi

  if [ "$(g -C "$t_wt" rev-parse HEAD)" != "$head" ] || [ -n "$(g -C "$t_wt" status --porcelain)" ]; then
    note="The review changed the worktree; the loop reset it to $head before merging."
    g -C "$t_wt" reset --quiet --hard "$head" || true
    g -C "$t_wt" clean --quiet -fd || true
  fi

  {
    printf '# Review of task %s: %s\n\n' "$t_id" "$t_title"
    printf -- '- Branch: %s at %s, against %s at %s\n' "$t_branch" "$head" "$target" "$base"
    printf -- '- Sensitive paths: %s\n' "$(paste -sd ' ' <<<"$touched")"
    printf -- '- Log: %s\n' "$(rel "$log")"
    if [ -n "$note" ]; then
      printf -- '- %s\n' "$note"
    fi
    echo
    if [ -n "$reason" ]; then
      printf 'Verdict: review failed: %s\n' "$reason"
    else
      printf '%s\n' "$result"
    fi
  } >"$report"
  : >"$run_dir/reviewed/$t_id"
  say "task $t_id: $(verdict_of "$report") ($(rel "$report"))"
}

verdict_of() {
  local verdict
  verdict="$(sed -n '/^Verdict:/{s/^Verdict:[[:space:]]*//p;q}' "$1")"
  echo "${verdict:-no verdict line}"
}

target_checkout() {
  g -C "$root" worktree list --porcelain |
    awk -v ref="branch refs/heads/$target" '/^worktree /{ p = substr($0, 10) } $0 == ref { print p; exit }'
}

merge_branch() {
  local attempt="$1" log tip head checkout conflicts rebased=0
  log="$(log_path "$attempt" merge.log)"
  lock_merge
  tip="$(g -C "$root" rev-parse "refs/heads/$target")"
  if ! g -C "$t_wt" merge-base --is-ancestor "$tip" HEAD; then
    say "task $t_id: $target moved on; rebasing onto it"
    if ! g -C "$t_wt" rebase "$tip" >>"$log" 2>&1; then
      conflicts="$(g -C "$t_wt" diff --name-only --diff-filter=U | paste -sd ' ')"
      g -C "$t_wt" rebase --abort >>"$log" 2>&1 || true
      unlock_merge
      failure="rebasing onto $target conflicts in ${conflicts:-some files}. Rebase this branch onto $target yourself (git rebase $target), resolve the conflicts keeping what both sides meant, and keep one commit for this task."
      return 1
    fi
    rebased=1
  fi
  if [ "$rebased" -eq 1 ]; then
    if ! run_gate "$attempt" gate-rebased; then
      unlock_merge
      failure="after the loop rebased the branch onto $target, $failure"
      return 1
    fi
  fi
  if ! guard "before merging"; then
    unlock_merge
    return 1
  fi

  head="$(g -C "$t_wt" rev-parse HEAD)"
  checkout="$(target_checkout)"
  if [ -n "$checkout" ]; then
    if [ -n "$(g -C "$checkout" status --porcelain --untracked-files=no)" ]; then
      unlock_merge
      fatal="$checkout, where $target is checked out, has uncommitted changes, so $target can't be fast-forwarded"
      say "task $t_id: $fatal; stopping. Commit or stash them, then 'ralph --resume $t_id'"
      return 1
    fi
    if ! g -C "$checkout" merge --ff-only --quiet "$head" >>"$log" 2>&1; then
      unlock_merge
      fatal="fast-forwarding $target in $checkout failed (log $(rel "$log"))"
      say "task $t_id: $fatal"
      return 1
    fi
  elif ! g -C "$root" update-ref -m "ralph: merge $t_branch" "refs/heads/$target" "$head" "$tip" >>"$log" 2>&1; then
    unlock_merge
    fatal="moving $target from $tip to $head failed (log $(rel "$log"))"
    say "task $t_id: $fatal"
    return 1
  fi
  say "task $t_id: merged into $target"

  if [ -n "$after_merge" ]; then
    if ! run_hook "$after_merge" "${checkout:-$root}" "$log" "RALPH_BEFORE=$tip" "RALPH_AFTER=$head"; then
      say "task $t_id: afterMerge failed; see $(rel "$log")"
    fi
  fi
  unlock_merge
}

attempt_with_services() {
  local attempt="$1" context="$2" status=0 log prompt base commits task_status
  prompt="$(log_path "$attempt" prompt.md)"
  render_prompt "$attempt" "$context" >"$prompt"
  log="$(log_path "$attempt" agent.jsonl)"
  build_agent_cmd
  say "task $t_id attempt $attempt: agent running (limit $task_timeout, log $(rel "$log"))"
  run_in "$log" 1 "$prompt" "${agent_cmd[@]}" || status=$?
  guard "after attempt $attempt" || return 1
  if [ "$status" -ne 0 ]; then
    failure="$(limit_reason "the agent" "$status"). Its last words:
$(agent_summary "$log")"
    return 1
  fi

  if [ -n "$(g -C "$t_wt" status --porcelain)" ]; then
    failure="the worktree has uncommitted changes after the agent finished:
$(g -C "$t_wt" status --short | head -n 40)"
    return 1
  fi

  base="$(g -C "$t_wt" merge-base HEAD "$target")"
  commits="$(g -C "$t_wt" rev-list --count "$base..HEAD")"
  if [ "$commits" -eq 0 ]; then
    failure="the agent made no commit"
    return 1
  fi

  task_status="$(field "$t_wt/$t_rel" status 2>/dev/null || true)"
  case "$task_status" in
    done) ;;
    blocked)
      blocked="$(section "$t_wt/$t_rel" "Open questions")"
      blocked="${blocked:-(the task file has no '## Open questions' section)}"
      return 1
      ;;
    *)
      failure="$t_rel says 'status: $task_status', expected done or blocked"
      return 1
      ;;
  esac

  run_gate "$attempt" gate || return 1
  guard "after the gate" || return 1
  review_branch "$attempt"
  guard "after the review" || return 1
  merge_branch "$attempt"
}

attempt_once() {
  local attempt="$1" context="$2" status=0 log
  failure=""
  blocked=""
  fatal=""
  log="$(log_path "$attempt" services.log)"
  if ! start_services "$log"; then
    failure="the services (\`$services_wrap\`) did not start. The end of their log:
$(tail -n 40 "$log")"
    return 1
  fi
  if [ -n "$services_wrap" ]; then
    say "task $t_id attempt $attempt: services up ($(printf '%s ' "${svc_env[@]%%=*}")log $(rel "$log"))"
  fi
  attempt_with_services "$attempt" "$context" || status=$?
  stop_services
  return "$status"
}

retry_context() {
  cat <<EOF
Attempt $1 at this task failed: $2

Everything from the previous attempt is still in this worktree. Fix the cause,
keep what was right, and amend the existing commit rather than adding another.
EOF
}

resume_context() {
  cat <<EOF
This task was stopped earlier and is being resumed in the same worktree. If it
was blocked, the open questions have been answered: read the task file's
"## Answers" section, and any new decisions in $decisions_dir on $target, before
continuing. Set the status to done once the task really is done, and amend the
existing commit.
EOF
  if [ -n "${1:-}" ]; then
    printf '\n%s\n' "$1"
  fi
}

remove_worktree() {
  if [ -e "$t_wt" ]; then
    g -C "$root" worktree remove --force --force "$t_wt" >/dev/null 2>&1 || true
  fi
  if [ -e "$t_wt" ]; then
    chmod -R u+w "$t_wt" 2>/dev/null || true
    rm -rf "$t_wt"
  fi
  g -C "$root" worktree prune
  if g -C "$root" rev-parse --verify --quiet "refs/heads/$t_branch" >/dev/null; then
    g -C "$root" branch --quiet -D "$t_branch"
  fi
}

current=""
current_attempt=0

work_on() {
  local context="$1" attempt=1 limit=$((retries + 1)) first
  current="$t_id"
  while :; do
    current_attempt="$attempt"
    if attempt_once "$attempt" "$context"; then
      remove_worktree
      rm -f "$(state_file "$t_id")"
      outcome merged
      current=""
      return 0
    fi

    if [ -n "$fatal" ]; then
      write_state failed "$fatal" "$attempt"
      outcome failed "$fatal"
      stop_run
      current=""
      return 1
    fi

    if [ -n "$blocked" ]; then
      write_state blocked "open questions in $t_rel" "$attempt"
      outcome blocked "answer the open questions in $t_wt/$t_rel"
      say "task $t_id is blocked on a decision. Its open questions:"
      printf '%s\n' "$blocked" >&2
      say "task $t_id: answer them under '## Answers' in $t_wt/$t_rel, then: ralph --resume $t_id"
      [ "$keep_going" = true ] || stop_run
      current=""
      return 1
    fi

    first="$(head -n 1 <<<"$failure")"
    if [ "$attempt" -ge "$limit" ]; then
      write_state failed "$first" "$attempt"
      outcome failed "$first"
      say "task $t_id failed after $attempt attempts: $first"
      say "task $t_id: the worktree is kept at $t_wt; look at it, then 'ralph --resume $t_id' or 'ralph --discard $t_id'"
      [ "$keep_going" = true ] || stop_run
      current=""
      return 1
    fi

    say "task $t_id attempt $attempt failed: $first"
    context="$(retry_context "$attempt" "$failure")"
    attempt=$((attempt + 1))
  done
}

start_task() {
  local log
  if [ -e "$t_wt" ] || g -C "$root" rev-parse --verify --quiet "refs/heads/$t_branch" >/dev/null; then
    write_state failed "a worktree or branch from an earlier run is in the way" 0
    outcome failed "$t_wt or $t_branch already exists"
    say "task $t_id: $t_wt or branch $t_branch already exists; 'ralph --resume $t_id' or 'ralph --discard $t_id'"
    return 1
  fi
  say "task $t_id: $t_title"
  mkdir -p "$worktree_dir" "$t_dir"
  log="$(log_path 0 setup.log)"
  if ! g -C "$root" worktree add --quiet -b "$t_branch" "$t_wt" "$target" >"$log" 2>&1; then
    write_state failed "git worktree add failed" 0
    outcome failed "git worktree add failed (log $(rel "$log"))"
    say "task $t_id: could not create its worktree; see $(rel "$log")"
    return 1
  fi
  if [ -n "$setup_cmd" ] && ! run_hook "$setup_cmd" "$t_wt" "$log"; then
    write_state failed "setup failed" 0
    outcome failed "setup failed (log $(rel "$log"))"
    say "task $t_id: setup failed; see $(rel "$log")"
    [ "$keep_going" = true ] || stop_run
    return 1
  fi
  work_on ""
}

resume_task() {
  local note="" conflicts
  lock_task "$1" || die "task $1 is running"
  refresh_tasks
  use_task "$1"
  [ -d "$t_wt" ] || die "there is no kept worktree at $t_wt; start the task normally"
  if ! g -C "$t_wt" merge-base --is-ancestor "$target" HEAD; then
    say "task $t_id: rebasing onto $target"
    if ! g -C "$t_wt" rebase "$target" >&2; then
      conflicts="$(g -C "$t_wt" diff --name-only --diff-filter=U | paste -sd ' ')"
      g -C "$t_wt" rebase --abort || true
      note="Rebasing this branch onto $target conflicts in ${conflicts:-some files}. Rebase it yourself (git rebase $target), resolve the conflicts keeping what both sides meant, and keep one commit for this task."
    fi
  fi
  rm -f "$(state_file "$t_id")"
  : >"$run_dir/claimed/$t_id"
  work_on "$(resume_context "$note")" || true
  unlock_task
}

run_one() {
  lock_task "$1" || die "task $1 is running"
  refresh_tasks
  use_task "$1"
  [ ! -f "$(state_file "$t_id")" ] || die "task $t_id has kept state; use --resume $t_id or --discard $t_id"
  grep -qx "$t_id" <<<"$(ready_ids)" ||
    die "task $t_id is not ready: it is '$(task_field "$t_id" 2)'$(w="$(waiting_on "$t_id")"; [ -z "$w" ] || printf ' and waits on %s' "$w")"
  : >"$run_dir/claimed/$t_id"
  start_task || true
  unlock_task
}

count() {
  local -a entries=("$1"/*)
  echo "${#entries[@]}"
}

claimed=""

claim_next() {
  local id
  claimed=""
  lock_pick
  if [ -e "$run_dir/stop" ]; then
    unlock_pick
    return 1
  fi
  if [ "$max_tasks" -gt 0 ] && [ "$(count "$run_dir/claimed")" -ge "$max_tasks" ]; then
    unlock_pick
    return 1
  fi
  refresh_tasks
  for id in $(ready_ids); do
    [ ! -f "$(state_file "$id")" ] || continue
    lock_task "$id" || continue
    refresh_tasks
    if [ ! -f "$(state_file "$id")" ] && grep -qx "$id" <<<"$(ready_ids)"; then
      claimed="$id"
      : >"$run_dir/claimed/$id"
      break
    fi
    unlock_task
  done
  unlock_pick
  [ -n "$claimed" ]
}

in_flight() {
  local f id
  for f in "$run_dir/claimed"/*; do
    id="$(basename "$f")"
    [ ! -e "$run_dir/outcomes/$id" ] || continue
    ! is_running "$id" || return 0
  done
  return 1
}

worker_stop() {
  local i
  trap '' TERM INT
  if [ -n "$child" ]; then
    kill -TERM -- "-$child" 2>/dev/null || kill -TERM "$child" 2>/dev/null || true
    for ((i = 0; i < 100; i++)); do
      kill -0 "$child" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL -- "-$child" 2>/dev/null || true
  fi
  stop_services
  if [ -n "$current" ] && [ ! -f "$run_dir/outcomes/$current" ]; then
    write_state failed "interrupted" "$current_attempt"
    outcome failed "interrupted"
  fi
  unlock_merge
  unlock_task
  exit 143
}

worker() {
  trap worker_stop TERM
  trap '' INT
  trap stop_services EXIT
  case "$1" in
    task)
      run_one "$2"
      return 0
      ;;
    resume) resume_task "$2" ;;
  esac
  while :; do
    if claim_next; then
      use_task "$claimed"
      start_task || true
      unlock_task
    elif [ ! -e "$run_dir/stop" ] && in_flight; then
      sleep 5
    else
      return 0
    fi
  done
}

print_reviews() {
  local id report
  [ "$#" -gt 0 ] || return 0
  echo "Reviews of sensitive branches in this run:"
  for id in "$@"; do
    report="$(task_dir "$id")/review.md"
    if [ ! -f "$report" ]; then
      printf '  %s  report missing: %s\n' "$id" "$(rel "$report")"
      continue
    fi
    printf '  %s  %s  %s\n' "$id" "$(verdict_of "$report")" "$(rel "$report")"
    section "$report" Findings | sed -n 's/^### */       - /p'
  done
}

reviewed_in() {
  local f
  for f in "$1/reviewed"/*; do
    basename "$f"
  done
}

summary() {
  local f id status reason
  local -a merged=() reviewed=()
  for f in "$run_dir/outcomes"/*; do
    id="$(basename "$f")"
    {
      read -r status
      read -r reason || true
    } <"$f"
    case "$status" in
      merged) merged+=("$id") ;;
      blocked) printf 'ralph: blocked  %s: %s\n' "$id" "$reason" >&2 ;;
      *) printf 'ralph: failed   %s: %s\n' "$id" "$reason" >&2 ;;
    esac
  done
  if [ "${#merged[@]}" -gt 0 ]; then
    say "merged ${merged[*]}"
  fi
  mapfile -t reviewed < <(reviewed_in "$run_dir")
  print_reviews "${reviewed[@]}" >&2
}

exit_status() {
  local f status worst=0
  for f in "$run_dir/outcomes"/*; do
    read -r status <"$f"
    case "$status" in
      failed) worst=1 ;;
      blocked) [ "$worst" -eq 1 ] || worst=3 ;;
    esac
  done
  echo "$worst"
}

print_status() {
  local id status title extra waits
  refresh_tasks
  while IFS="$tab" read -r id status _ title _; do
    [ -n "$id" ] || continue
    [ "${1:-}" != pending ] || [ "$status" != "done" ] || continue
    extra=""
    if is_running "$id"; then
      extra="[running]"
    elif [ -f "$(state_file "$id")" ]; then
      extra="$(jq -r '"[\(.status)] \(.reason)"' "$(state_file "$id")")"
    elif [ "$status" = todo ]; then
      waits="$(waiting_on "$id")"
      [ -z "$waits" ] || extra="(waits on $waits)"
    fi
    printf '%s  %-8s %s %s\n' "$id" "${status:-?}" "$title" "$extra"
  done <<<"$tasks_tsv"
}

print_config() {
  jq -n \
    --arg configFile "$config_file" \
    --arg root "$root" \
    --arg target "$target" \
    --arg tasksDir "$tasks_dir" \
    --arg decisionsDir "$decisions_dir" \
    --arg worktreeDir "$worktree_dir" \
    --arg stateDir "$state_dir" \
    --arg branchPrefix "$branch_prefix" \
    --arg gate "$gate" \
    --arg setup "$setup_cmd" \
    --arg afterMerge "$after_merge" \
    --arg servicesWrap "$services_wrap" \
    --arg timeout "$task_timeout" \
    --arg retries "$retries" \
    --arg jobs "$jobs" \
    --arg maxTasks "$max_tasks" \
    --arg model "$model" \
    --arg keepGoing "$keep_going" \
    --arg sandbox "$sandbox_mode" \
    --arg prompt "$prompt_file" \
    --arg reviewPrompt "$review_file" \
    --arg instructions "$instructions_file" \
    --arg reviewInstructions "$review_instructions_file" \
    --argjson settings "$settings" \
    '{configFile: $configFile, root: $root, target: $target, tasksDir: $tasksDir, decisionsDir: $decisionsDir,
      worktreeDir: $worktreeDir, stateDir: $stateDir, branchPrefix: $branchPrefix, gate: $gate, setup: $setup,
      afterMerge: $afterMerge, services: {wrap: $servicesWrap}, timeout: $timeout, retries: ($retries | tonumber),
      jobs: ($jobs | tonumber), maxTasks: ($maxTasks | tonumber), model: $model, keepGoing: ($keepGoing == "true"),
      sandbox: {mode: $sandbox}, prompt: $prompt, reviewPrompt: $reviewPrompt, instructions: $instructions,
      reviewInstructions: $reviewInstructions, settings: $settings}' |
    jq --argjson c "$config" '
      .services.env = ($c.services.env // [])
      | .sandbox += {command: ($c.sandbox.command // "sandbox-ai"), rw: ($c.sandbox.rw // ["~/.cache/nix"]), ro: ($c.sandbox.ro // []), rox: ($c.sandbox.rox // [])}
      | .env = ($c.env // {}) | .unsetEnv = ($c.unsetEnv // []) | .agentArgs = ($c.agentArgs // [])
      | .sensitivePaths = ($c.sensitivePaths // [".ralph/", ".claude/", ".mcp.json", ".envrc", ".github/", ".config/wt.toml"])'
}

review_plan() {
  local base touched
  if [ "${#sensitive[@]}" -eq 0 ]; then
    echo "none: sensitivePaths is empty"
  elif ! g -C "$root" rev-parse --quiet --verify "refs/heads/$t_branch" >/dev/null; then
    echo "after the gate, if the branch's diff against $target touches any of: ${sensitive[*]}"
  else
    base="$(g -C "$root" merge-base "$t_branch" "$target")"
    touched="$(g -C "$root" diff --no-ext-diff --no-renames --name-only "$base" "$t_branch" -- "${sensitive[@]}")"
    if [ -n "$touched" ]; then
      echo "scheduled after the gate: $t_branch touches $(paste -sd ' ' <<<"$touched")"
    else
      echo "none: $t_branch touches no sensitive path"
    fi
  fi
}

dry_run() {
  local id="" candidate prefix=""
  refresh_tasks
  for candidate in $(ready_ids); do
    [ ! -f "$(state_file "$candidate")" ] || continue
    is_running "$candidate" && continue
    id="$candidate"
    break
  done
  [ -n "$id" ] || die "no task is ready"
  use_task "$id"
  build_sandbox_args
  build_agent_cmd
  if [ "$sandbox_mode" = wrap ]; then
    prefix="${sandbox_cmd[*]} -l ${sandbox_args[*]} --env … -- "
  fi
  echo "task:      $t_id  $t_title"
  echo "file:      $t_rel on $target"
  echo "depends:   $(task_field "$t_id" 3)"
  echo "branch:    $t_branch"
  echo "worktree:  $t_wt"
  echo "setup:     ${setup_cmd:-none}"
  echo "sandbox:   $sandbox_mode"
  echo "services:  ${services_wrap:-none}${services_wrap:+ (gives ${svc_keys[*]:-no variables})}"
  echo "agent:     $prefix${claude_cmd[*]} -p --dangerously-skip-permissions --settings '$settings' --output-format stream-json --verbose${model:+ --model $model}${agent_args[*]:+ ${agent_args[*]}} < prompt"
  echo "gate:      ${gate:-none set}"
  echo "review:    $(review_plan)"
  echo "merge:     fast-forward $target$(c="$(target_checkout)"; [ -z "$c" ] || printf ' in %s' "$c")${after_merge:+, then afterMerge: $after_merge}"
  echo "---- prompt ----"
  render_prompt 1 ""
}

discard_task() {
  lock_task "$1" || die "task $1 is running"
  refresh_tasks
  use_task "$1"
  remove_worktree
  rm -f "$(state_file "$t_id")"
  unlock_task
  say "task $t_id discarded; it starts fresh next time"
}

last_run() {
  local -a dirs=("$runs"/*/)
  [ "${#dirs[@]}" -gt 0 ] || return 0
  printf '%s\n' "${dirs[@]%/}" | sort | tail -n 1
}

case "$mode" in
  status)
    print_status
    exit 0
    ;;
  config)
    print_config
    exit 0
    ;;
  dry-run)
    dry_run
    exit 0
    ;;
  discard)
    discard_task "$chosen"
    exit 0
    ;;
  reviews)
    last="$(last_run)"
    if [ -z "$last" ]; then
      echo "No run has been recorded yet."
      exit 0
    fi
    mapfile -t ids < <(reviewed_in "$last")
    if [ "${#ids[@]}" -eq 0 ]; then
      echo "The last run reviewed no branch. Earlier reports stay in $(rel "$state_dir/tasks")/<id>/review.md."
      exit 0
    fi
    print_reviews "${ids[@]}"
    exit 0
    ;;
esac

[ -n "$gate" ] || die "no gate is set; put the command that must pass before a merge in gate in $config_file (\"true\" merges without one)"
timeout_bin="$(command -v timeout)" || die "timeout is not on PATH"
for tool in jq flock; do
  command -v "$tool" >/dev/null || die "$tool is not on PATH"
done
PATH="$user_path" command -v "${claude_cmd[0]}" >/dev/null || die "${claude_cmd[0]} is not on PATH"
if [ "$sandbox_mode" = wrap ]; then
  PATH="$user_path" command -v "${sandbox_cmd[0]}" >/dev/null ||
    die "${sandbox_cmd[0]} is not on PATH; set sandbox.command, or pass --in-sandbox if this already runs inside a sandbox"
  if sandboxed_now; then
    say "warning: this already runs inside a sandbox, and iterations get a second one; --in-sandbox shares this one instead"
  fi
elif [ "$sandbox_mode" = none ]; then
  say "warning: sandbox.mode is none, so iterations run with --dangerously-skip-permissions and no sandbox"
fi
[ -f "$prompt_file" ] || die "no prompt template at $prompt_file"

checkout="$(target_checkout)"
if [ -n "$checkout" ] && [ -n "$(g -C "$checkout" status --porcelain --untracked-files=no)" ]; then
  die "$checkout has $target checked out with uncommitted changes; the loop could not fast-forward it"
fi
for dir in "$worktree_dir" "$state_dir"; do
  case "$dir" in
    "$root"/*)
      g -C "$root" check-ignore -q "$dir/" ||
        say "warning: $(rel "$dir") is not ignored by git; add it to .gitignore"
      ;;
  esac
done

case "$mode" in
  once)
    jobs=1
    max_tasks=1
    ;;
  task) jobs=1 ;;
esac

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_dir="$runs/$run_id"
mkdir -p "$run_dir/claimed" "$run_dir/outcomes" "$run_dir/reviewed" "$locks" "$worktree_dir"
fingerprint >"$run_dir/fingerprint"
build_sandbox_args

say "run $run_id: target $target, sandbox $sandbox_mode, $jobs job(s), logs in $(rel "$state_dir")/tasks/<id>/"

workers=()
on_signal() {
  trap '' INT TERM
  stop_run
  say "interrupted; stopping the running tasks"
  kill -TERM "${workers[@]}" 2>/dev/null || true
  for pid in "${workers[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  summary
  exit 130
}
trap on_signal INT TERM

for ((k = 1; k <= jobs; k++)); do
  if [ "$k" -eq 1 ]; then
    case "$mode" in
      task) worker task "$chosen" &
      ;;
      resume) worker resume "$chosen" &
      ;;
      *) worker loop "" &
      ;;
    esac
  else
    worker loop "" &
  fi
  workers+=("$!")
done

crashed=0
for pid in "${workers[@]}"; do
  wait "$pid" || crashed=1
done

summary
status="$(exit_status)"
if [ "$status" -eq 0 ] && [ "$crashed" -eq 1 ]; then
  status=1
elif [ "$status" -eq 0 ] && [ "$(count "$run_dir/outcomes")" -eq 0 ]; then
  say "no task is ready"
  print_status pending >&2
fi
exit "$status"
