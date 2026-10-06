tmp="$(mktemp -d "${TMPDIR:-/tmp}/ralph-test.XXXXXX")"
trap '[ -n "${RALPH_TEST_KEEP:-}" ] || { chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"; }' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
stubs="$tmp/bin"
mkdir -p "$stubs"
export PATH="$stubs:$PATH"
passed=0

fail() {
  echo "ralph-test: FAIL: $*" >&2
  exit 1
}

ok() {
  passed=$((passed + 1))
  echo "ralph-test: ok: $*"
}

has() {
  grep -qF -- "$2" <<<"$1" || fail "$3: expected '$2' in:
$1"
}

lacks() {
  ! grep -qF -- "$2" <<<"$1" || fail "$3: did not expect '$2' in:
$1"
}

stub() {
  {
    printf '#!%s\n' "$BASH"
    cat
  } >"$stubs/$1"
  chmod +x "$stubs/$1"
}

stub claude <<'STUB'
set -euo pipefail
prompt="$(cat)"
log="$RALPH_TEST_LOG"
id="$RALPH_TASK_ID"
files=(docs/tasks/"$id"-*.md)
file="${files[0]}"
want() {
  sed -n "s/^$1: //p" "$file" | head -n 1
}
echo "$$" >"$log/$id.pid"

if grep -q 'adversarial reviewer' <<<"$prompt"; then
  echo review >>"$log/$id.calls"
  printf '%s\n' "$prompt" >"$log/$id.review-prompt"
  if [ "$(want review)" = fail ]; then
    echo probe >review-probe.txt
    git add review-probe.txt
    git commit --quiet -m "Probe the branch"
    echo probe >stray.txt
    exit 3
  fi
  jq -nc --arg id "$id" '{type: "result", subtype: "success", is_error: false, result: "Verdict: issues found\n\n## Scope\n\nTask \($id).\n\n## Findings\n\n### major: task \($id) weakens the gate\n\nThe scenario.\n\n## Checked and held\n\n### the gate still runs\n"}'
  exit 0
fi

echo agent >>"$log/$id.calls"
printf '%s\n' "$prompt" >"$log/$id.prompt"
env | sort >"$log/$id.env"
attempt="$(sed -n 's/^- Attempt: \([0-9]*\)\..*/\1/p' <<<"$prompt")"
pause="$(want sleep)"
[ -z "$pause" ] || sleep "$pause"

resolve() {
  local f
  for f in $(git diff --name-only --diff-filter=U); do
    sed -i '/^<<<<<<< /d; /^=======$/d; /^>>>>>>> /d' "$f"
    git add "$f"
  done
}

if grep -q 'Rebase this branch onto' <<<"$prompt"; then
  if ! git rebase --quiet "$RALPH_TARGET" >/dev/null 2>&1; then
    resolve
    GIT_EDITOR=true git rebase --continue >/dev/null
  fi
  jq -nc '{type: "result", subtype: "success", is_error: false, result: "rebased"}'
  exit 0
fi

commit() {
  git add -A
  if [ "$(git rev-list --count "$RALPH_TARGET..HEAD")" -gt 0 ]; then
    git commit --quiet --amend --no-edit
  else
    git commit --quiet -m "Do $id"
  fi
}

case "$(want act)" in
  block)
    if ! grep -q 'being resumed' <<<"$prompt"; then
      sed -i 's/^status: todo$/status: blocked/' "$file"
      printf '\n## Open questions\n\n1. Red or blue?\n' >>"$file"
      commit
      jq -nc '{type: "result", subtype: "success", is_error: false, result: "blocked"}'
      exit 0
    fi
    grep -q '^## Answers' "$file" || exit 9
    sed -i 's/^status: blocked$/status: done/' "$file"
    ;;
  crash)
    jq -nc '{type: "result", subtype: "error", is_error: true, result: "the agent gave up"}'
    exit 1
    ;;
  nocommit)
    jq -nc '{type: "result", subtype: "success", is_error: false, result: "nothing"}'
    exit 0
    ;;
  fail-once)
    if [ "$attempt" = 1 ]; then
      touch .gate-fail
    else
      rm -f .gate-fail
    fi
    ;;
esac

touched="$(want touch)"
if [ -n "$touched" ]; then
  mkdir -p "$(dirname "$touched")"
  echo "$id" >>"$touched"
fi
sed -i 's/^status: todo$/status: done/' "$file"
commit

case "$(want act)" in
  hook) echo 'exit 0' >"$(git rev-parse --path-format=absolute --git-common-dir)/hooks/post-merge" ;;
  config) git config core.hooksPath .githooks ;;
  worktree-config)
    git config extensions.worktreeConfig true
    git config --worktree core.hooksPath .githooks
    ;;
esac
jq -nc '{type: "result", subtype: "success", is_error: false, result: "done"}'
STUB

stub sandbox-stub <<'STUB'
set -euo pipefail
[ "$1" = -l ] || exit 64
shift
args=()
while [ "$1" != -- ]; do
  args+=("$1")
  shift
done
shift
printf '%s\n' "${args[*]}" >>"$RALPH_TEST_LOG/sandbox"
exec "$@"
STUB

stub fake-svc <<'STUB'
set -uo pipefail
export FAKE_PORT="$((20000 + RANDOM % 1000))" FAKE_DIR="$PWD/.tmp/svc-$RANDOM"
mkdir -p "$FAKE_DIR"
echo "up $RALPH_TASK_ID $FAKE_DIR" >>"$RALPH_TEST_LOG/services"
[ "${1:-}" != -- ] || shift
"$@"
status=$?
echo "down $RALPH_TASK_ID $FAKE_DIR" >>"$RALPH_TEST_LOG/services"
rm -rf "$FAKE_DIR"
exit "$status"
STUB


repo() {
  local name="$1" spec id slug extra
  shift
  local dir="$tmp/$name"
  mkdir -p "$dir/docs/tasks" "$dir/.ralph" "$tmp/$name.log"
  git init --quiet -b master "$dir"
  git -C "$dir" config user.name ralph-test
  git -C "$dir" config user.email ralph-test@localhost
  printf '.tmp/\n' >"$dir/.gitignore"
  printf 'base\n' >"$dir/shared.txt"
  jq -n '{gate: "test ! -e .gate-fail && echo gate-ok >>\"$RALPH_TEST_LOG/gates\"", sandbox: {mode: "inherit"}, retries: 0, timeout: "2m"}' >"$dir/.ralph/config.json"
  for spec in "$@"; do
    IFS='|' read -r slug extra <<<"$spec"
    id="${slug%%-*}"
    printf -- '---\nid: %s\ntitle: Task %s\nstatus: todo\n%b\n---\n\n# %s\n' "$id" "$slug" "$extra" "$slug" >"$dir/docs/tasks/$slug.md"
  done
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m "Start"
}

configure() {
  local dir="$tmp/$1" filter="$2"
  jq "$filter" "$dir/.ralph/config.json" >"$dir/.ralph/config.json.new"
  mv "$dir/.ralph/config.json.new" "$dir/.ralph/config.json"
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m "Configure"
}

ralph_in() {
  local name="$1"
  shift
  (
    cd "$tmp/$name"
    RALPH_TEST_LOG="$tmp/$name.log" ralph "$@"
  ) 2>&1
}

subjects() {
  git -C "$tmp/$1" log --format=%s master
}

repo dry "001-first|depends: -\ntouch: src/a.txt" "002-second|depends: 001\ntouch: .claude/settings.json"
out="$(ralph_in dry --dry-run)" || fail "dry run: $out"
has "$out" "task:      001  Task 001-first" "the dry run"
has "$out" "branch:    ralph/001-first" "the dry run"
has "$out" "review:    after the gate, if the branch's diff against master touches any of: .ralph/ .claude/" "the dry run"
has "$out" "Task: **001 — Task 001-first**, described in \`docs/tasks/001-first.md\`" "the dry run's prompt"
has "$out" "This is the first attempt at this task." "the dry run's prompt"
lacks "$out" "{{" "the dry run's prompt"
[ ! -e "$tmp/dry/.tmp/worktrees" ] || fail "a dry run created worktrees"
status="$(ralph_in dry --status)"
has "$status" "002  todo     Task 002-second (waits on 001)" "the status"
ok "a dry run plans the next task and renders its prompt without changing anything"

repo seq "001-first|depends: -\ntouch: src/a.txt" \
  "002-second|depends: 001\ntouch: .claude/settings.json" \
  "003-third|depends: 002\ntouch: .envrc\nreview: fail"
out="$(ralph_in seq)" || fail "the loop over three dependent tasks: $out"
log="$(subjects seq)"
for id in 001 002 003; do
  has "$log" "Do $id" "master after the loop"
done
[ "$(head -n 1 <<<"$log")" = "Do 003" ] || fail "tasks merged out of order: $log"
[ -z "$(git -C "$tmp/seq" rev-list --merges master)" ] || fail "master has merge commits"
lacks "$log" "Probe the branch" "master after a review that committed"
[ ! -e "$tmp/seq/stray.txt" ] && [ ! -e "$tmp/seq/review-probe.txt" ] || fail "a review's changes reached master"
[ "$(git -C "$tmp/seq" worktree list | wc -l)" -eq 1 ] || fail "worktrees were left behind"
[ -z "$(git -C "$tmp/seq" branch --list 'ralph/*')" ] || fail "branches were left behind"
reviews="$tmp/seq/.tmp/ralph/tasks"
[ ! -e "$reviews/001/review.md" ] || fail "a branch touching only src/ was reviewed"
has "$(cat "$reviews/002/review.md")" "### major: task 002 weakens the gate" "the kept report"
has "$(cat "$tmp/seq.log/002.review-prompt")" "- \`.claude/settings.json\`" "the review's prompt"
lacks "$(cat "$tmp/seq.log/002.review-prompt")" "{{" "the review's prompt"
has "$(cat "$reviews/003/review.md")" "Verdict: review failed: the review exited with status 3" "the failed review's record"
has "$(cat "$reviews/003/review.md")" "The review changed the worktree" "the failed review's record"
for summary in "$out" "$(ralph_in seq --reviews)"; do
  has "$summary" "002  issues found  .tmp/ralph/tasks/002/review.md" "the review summary"
  has "$summary" "- major: task 002 weakens the gate" "the review summary"
  has "$summary" "003  review failed: the review exited with status 3" "the review summary"
  lacks "$summary" "the gate still runs" "the review summary"
done
has "$out" "merged 001 002 003" "the loop's summary"
[ "$(wc -l <"$tmp/seq.log/gates")" -eq 3 ] || fail "expected three gate runs"
env_seen="$(cat "$tmp/seq.log/001.env")"
has "$env_seen" "GIT_CONFIG_KEY_0=commit.gpgSign" "the agent's environment"
has "$env_seen" "RALPH_BRANCH=ralph/001-first" "the agent's environment"
ok "the loop merges dependent tasks in order, reviews sensitive branches, keeps and summarises the reports, and cleans up"

repo blocked "001-ask|depends: -\nact: block" "002-free|depends: -\ntouch: b.txt" "003-after|depends: 001\ntouch: c.txt"
status=0
out="$(ralph_in blocked)" || status=$?
[ "$status" -eq 3 ] || fail "a blocked task made the loop exit $status, not 3: $out"
has "$out" "1. Red or blue?" "the blocked task's questions"
lacks "$(subjects blocked)" "Do 002" "master after a block without --keep-going"
has "$(ralph_in blocked --status)" "001  todo     Task 001-ask [blocked] open questions in docs/tasks/001-ask.md" "the status after a block"
wt="$tmp/blocked/.tmp/worktrees/ralph-001-ask"
printf '\n## Answers\n\n1. Blue.\n' >>"$wt/docs/tasks/001-ask.md"
git -C "$wt" commit --quiet -am "Answer"
out="$(ralph_in blocked --resume 001)" || fail "resuming the answered task: $out"
log="$(subjects blocked)"
for id in 001 002 003; do
  has "$log" "Do $id" "master after resuming"
done
has "$(cat "$tmp/blocked.log/001.prompt")" "being resumed" "the resumed prompt"
ok "a blocked task stops the loop with its questions, and --resume finishes it and carries on"

repo keep "001-ask|depends: -\nact: block" "002-free|depends: -\ntouch: b.txt" "003-crash|depends: -\nact: crash" "004-after|depends: 001\ntouch: c.txt"
status=0
out="$(ralph_in keep --keep-going)" || status=$?
[ "$status" -eq 1 ] || fail "a failure and a block with --keep-going exited $status, not 1: $out"
has "$(subjects keep)" "Do 002" "master after --keep-going"
lacks "$(subjects keep)" "Do 004" "master after --keep-going"
has "$out" "failed   003: the agent exited with status 1" "the summary"
has "$out" "blocked  001" "the summary"
has "$(cat "$tmp/keep/.tmp/ralph/tasks/003/state.json")" '"status": "failed"' "the failed task's state"
ralph_in keep --discard 003 >/dev/null || fail "discarding 003"
[ ! -e "$tmp/keep/.tmp/worktrees/ralph-003-crash" ] || fail "--discard left the worktree"
[ -z "$(git -C "$tmp/keep" branch --list 'ralph/003-*')" ] || fail "--discard left the branch"
lacks "$(ralph_in keep --status)" "003  todo     Task 003-crash [" "the status after --discard"
ok "--keep-going passes a failure and a block, and --discard clears the failed task"

repo retry "001-flaky|depends: -\nact: fail-once\ntouch: d.txt"
configure retry '.retries = 1'
out="$(ralph_in retry)" || fail "a task whose first gate fails: $out"
has "$(subjects retry)" "Do 001" "master after a retry"
[ "$(git -C "$tmp/retry" rev-list --count master)" -eq 3 ] || fail "the retry added a second commit"
has "$(cat "$tmp/retry.log/001.prompt")" "Attempt 1 at this task failed: the gate (\`test ! -e .gate-fail" "the retry's prompt"
ok "a failed gate is retried with its output in the prompt, and the retry amends"

for act in hook config worktree-config; do
  repo "guard-$act" "001-sneaky|depends: -\nact: $act\ntouch: e.txt"
  start="$(git -C "$tmp/guard-$act" rev-parse master)"
  status=0
  out="$(ralph_in "guard-$act")" || status=$?
  [ "$status" -eq 1 ] || fail "planting $act exited $status, not 1: $out"
  [ "$(git -C "$tmp/guard-$act" rev-parse master)" = "$start" ] || fail "the loop merged after $act"
  has "$out" "code could run outside the sandbox" "the loop after $act"
  has "$(cat "$tmp/guard-$act/.tmp/ralph/tasks/001/state.json")" '"status": "failed"' "the state after $act"
done
has "$(cat "$tmp/guard-hook/.tmp/ralph/tasks/001/state.json")" "added: .git/hooks/post-merge" "the state after a planted hook"
has "$(cat "$tmp/guard-config/.tmp/ralph/tasks/001/state.json")" "changed: .git/config" "the state after a config change"
ok "a planted hook, a hooksPath change or a worktree config stops the loop without merging"

repo par "001-a|depends: -\nsleep: 2\ntouch: a.txt" "002-b|depends: -\nsleep: 2\ntouch: b.txt" \
  "003-c|depends: -\nsleep: 2\ntouch: c.txt" "004-d|depends: 001, 002, 003\ntouch: d.txt"
started=$SECONDS
out="$(ralph_in par --jobs 3)" || fail "three parallel tasks: $out"
elapsed=$((SECONDS - started))
log="$(subjects par)"
for id in 001 002 003 004; do
  has "$log" "Do $id" "master after a parallel run"
done
[ "$(head -n 1 <<<"$log")" = "Do 004" ] || fail "004 merged before its dependencies"
[ -z "$(git -C "$tmp/par" rev-list --merges master)" ] || fail "master has merge commits"
[ "$elapsed" -lt 10 ] || fail "three 2 s tasks on three jobs took ${elapsed}s"
has "$out" "moved on; rebasing onto it" "a parallel run"
rebased=("$tmp"/par/.tmp/ralph/tasks/*/*.gate-rebased.log)
[ "${#rebased[@]}" -ge 1 ] || fail "no branch was gated again after rebasing"
for id in 001 002 003 004; do
  [ "$(grep -c agent "$tmp/par.log/$id.calls")" -eq 1 ] || fail "task $id ran more than once"
done
ok "--jobs 3 runs independent tasks at once, rebases and re-gates late branches, and holds dependants back (${elapsed}s)"

repo twice "001-a|depends: -\nsleep: 2\ntouch: a.txt" "002-b|depends: -\nsleep: 2\ntouch: b.txt"
ralph_in twice >"$tmp/twice.one" &
one=$!
ralph_in twice >"$tmp/twice.two" &
two=$!
wait "$one" || fail "the first of two concurrent runs: $(cat "$tmp/twice.one")"
wait "$two" || fail "the second of two concurrent runs: $(cat "$tmp/twice.two")"
for id in 001 002; do
  has "$(subjects twice)" "Do $id" "master after two concurrent runs"
  [ "$(grep -c agent "$tmp/twice.log/$id.calls")" -eq 1 ] || fail "two concurrent runs both ran task $id"
done
ok "two concurrent invocations split the ready tasks between them"

repo conflict "001-a|depends: -\nsleep: 1\ntouch: shared.txt" "002-b|depends: -\nsleep: 1\ntouch: shared.txt"
status=0
out="$(ralph_in conflict --jobs 2 --keep-going)" || status=$?
[ "$status" -eq 1 ] || fail "two tasks editing one line exited $status, not 1: $out"
has "$out" "conflicts in shared.txt" "the conflicting task"
repo conflict2 "001-a|depends: -\nsleep: 1\ntouch: shared.txt" "002-b|depends: -\nsleep: 1\ntouch: shared.txt"
configure conflict2 '.retries = 1'
out="$(ralph_in conflict2 --jobs 2)" || fail "a conflict the retry resolves: $out"
merged="$(git -C "$tmp/conflict2" show master:shared.txt)"
has "$merged" "001" "shared.txt after the resolved conflict"
has "$merged" "002" "shared.txt after the resolved conflict"
ok "a rebase conflict fails the attempt, and a retry that rebases and resolves it merges"

repo svc "001-a|depends: -\ntouch: a.txt\nact: fail-once"
configure svc '.retries = 1 | .services = {wrap: "fake-svc --", env: ["FAKE_PORT", "FAKE_DIR", "NOT_SET"]}'
out="$(ralph_in svc)" || fail "a task with services: $out"
seen="$(cat "$tmp/svc.log/001.env")"
has "$seen" "FAKE_PORT=" "the agent's environment with services"
lacks "$seen" "NOT_SET=" "the agent's environment with services"
[ "$(grep -c '^up 001' "$tmp/svc.log/services")" -eq 2 ] || fail "expected services for each of two attempts"
[ "$(grep -c '^down 001' "$tmp/svc.log/services")" -eq 2 ] || fail "services were not torn down after each attempt"
has "$(cat "$tmp/svc.log/001.prompt")" "started by the loop with \`fake-svc --\`" "the prompt with services"
[ -z "$(ls -A "$tmp/svc/.tmp" 2>/dev/null | grep svc || true)" ] || fail "the services' directory was left behind"
ok "services start per attempt, their variables reach the agent, and they are torn down"

repo side "001-a|depends: -\ntouch: a.txt"
git -C "$tmp/side" switch --quiet -c side
configure side '.target = "master"'
out="$(ralph_in side)" || fail "a target not checked out: $out"
has "$(subjects side)" "Do 001" "master when the main checkout is on another branch"
[ "$(git -C "$tmp/side" symbolic-ref --short HEAD)" = side ] || fail "the main checkout left its branch"
[ ! -e "$tmp/side/a.txt" ] || fail "the main checkout's files changed"
ok "a target that isn't checked out is moved with a compare-and-swap"

repo dirty "001-a|depends: -\ntouch: a.txt"
echo dirty >>"$tmp/dirty/shared.txt"
status=0
out="$(ralph_in dirty)" || status=$?
[ "$status" -ne 0 ] || fail "the loop ran with uncommitted changes in the target's checkout"
has "$out" "uncommitted changes" "the loop with a dirty checkout"
ok "uncommitted changes where the target is checked out stop the loop before it starts"

repo wrap "001-a|depends: -\ntouch: .ralph/notes.md"
configure wrap '.sandbox = {mode: "wrap", command: "sandbox-stub", rw: ["~/does-not-exist"], ro: ["docs"]} | .env = {PARTITION: "_r{{TASK_ID}}"}'
out="$(ralph_in wrap)" || fail "the loop in wrap mode: $out"
args="$(cat "$tmp/wrap.log/sandbox")"
has "$args" "--rw $tmp/wrap/.git" "the sandbox's arguments"
has "$args" "--ro $tmp/wrap/docs" "the sandbox's arguments"
has "$args" "--env RALPH_TASK_ID" "the sandbox's arguments"
has "$args" "--env PARTITION" "the sandbox's arguments"
lacks "$args" "does-not-exist" "the sandbox's arguments"
[ "$(wc -l <<<"$args")" -eq 3 ] || fail "expected the agent, the gate and the review to be sandboxed: $args"
has "$(cat "$tmp/wrap.log/001.env")" "PARTITION=_r001" "the agent's environment"
ok "wrap mode sandboxes the agent, the gate and the review with the configured paths and environment"

repo notready "001-a|depends: -\ntouch: a.txt" "002-b|depends: 001\ntouch: b.txt"
status=0
out="$(ralph_in notready --task 002)" || status=$?
[ "$status" -ne 0 ] || fail "--task on a task that isn't ready succeeded"
has "$out" "task 002 is not ready: it is 'todo' and waits on 001" "--task on a waiting task"
out="$(ralph_in notready --task 001)" || fail "--task 001: $out"
lacks "$(subjects notready)" "Do 002" "master after --task 001"
ok "--task runs exactly the named task, and refuses one that isn't ready"

repo stop "001-slow|depends: -\nsleep: 30\ntouch: a.txt"
configure stop '.services = {wrap: "fake-svc --", env: ["FAKE_PORT"]}'
(
  cd "$tmp/stop"
  exec env --default-signal=INT RALPH_TEST_LOG="$tmp/stop.log" ralph
) >"$tmp/stop.out" 2>&1 &
loop=$!
for _ in $(seq 100); do
  [ -s "$tmp/stop.log/001.pid" ] && break
  sleep 0.1
done
[ -s "$tmp/stop.log/001.pid" ] || fail "the slow task's agent never started: $(cat "$tmp/stop.out")"
kill -INT "$loop"
status=0
wait "$loop" || status=$?
[ "$status" -eq 130 ] || fail "an interrupted loop exited $status, not 130: $(cat "$tmp/stop.out")"
! kill -0 "$(cat "$tmp/stop.log/001.pid")" 2>/dev/null || fail "the agent outlived the loop"
has "$(cat "$tmp/stop.log/services")" "down 001" "the services after an interrupt"
has "$(cat "$tmp/stop/.tmp/ralph/tasks/001/state.json")" '"reason": "interrupted"' "the state after an interrupt"
ok "an interrupt stops the agent and the services and keeps the task for --resume"

echo "ralph-test: all $passed scenarios passed"
