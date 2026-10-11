tmp="$(mktemp -d "${TMPDIR:-/tmp}/ralph-test.XXXXXX")"
trap '[ -n "${RALPH_TEST_KEEP:-}" ] || { chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"; }' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset RALPH_CONFIG RALPH_TARGET RALPH_AGENT RALPH_REVIEW_AGENT RALPH_TIMEOUT RALPH_RETRIES RALPH_JOBS RALPH_MAX_TASKS
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

stub fake-agent <<'STUB'
set -euo pipefail
[ "${1:-}" != --stub-probe ] || exec echo stub
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
  printf '%s\n' "$*" >"$log/$id.review-argv"
  case "$(want review)" in
    fail)
      echo probe >review-probe.txt
      git add review-probe.txt
      git commit --quiet -m "Probe the branch"
      echo probe >stray.txt
      exit 3
      ;;
    silent) exit 0 ;;
    late) code=3 ;;
  esac
  report="$(grep -o '/[^`]*review-report\.md' <<<"$prompt" | head -n 1)"
  printf 'Verdict: issues found\n\n## Scope\n\nTask %s.\n\n## Findings\n\n### major: task %s weakens the gate\n\nThe scenario.\n\n## Checked and held\n\n### the gate still runs\n' "$id" "$id" >"$report"
  echo "the report is in $report"
  exit "${code:-0}"
fi

echo agent >>"$log/$id.calls"
printf '%s\n' "$prompt" >"$log/$id.prompt"
printf '%s\n' "$*" >"$log/$id.argv"
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
  echo rebased
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
      echo blocked
      exit 0
    fi
    grep -q '^## Answers' "$file" || exit 9
    sed -i 's/^status: blocked$/status: done/' "$file"
    ;;
  crash)
    echo "the agent gave up"
    exit 1
    ;;
  nocommit)
    echo nothing
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
echo done
STUB
[ "$("$stubs/fake-agent" --stub-probe </dev/null 2>/dev/null)" = stub ] ||
  fail "$stubs/fake-agent can't be executed; point TMPDIR at a directory that allows exec"
for agent in claude opencode; do
  stub "$agent" <<'STUB'
echo "ralph-test: ${0##*/} was started; the ralph under test is not the one these tests are for" >&2
exit 97
STUB
done

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
  jq -n '{gate: "test ! -e .gate-fail && echo gate-ok >>\"$RALPH_TEST_LOG/gates\"", agent: "fake-agent", retries: 0, timeout: "2m"}' >"$dir/.ralph/config.json"
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
    cd "$tmp/$name" || exit 1
    RALPH_TEST_LOG="$tmp/$name.log" ralph "$@"
  ) 2>&1
}

subjects() {
  git -C "$tmp/$1" log --format=%s master
}

repo dry "001-first|depends: -\ntouch: src/a.txt" "002-second|depends: 001\ntouch: .claude/settings.json"
printf 'Attempt {{ATTEMPT}} of {{TASK_ID}}.\n' >"$tmp/dry/.ralph/instructions.md"
out="$(ralph_in dry --dry-run)" || fail "dry run: $out"
has "$out" "Attempt 1 of 001." "the dry run's instructions"
has "$out" "task:      001  Task 001-first" "the dry run"
has "$out" "branch:    ralph/001-first" "the dry run"
has "$out" "review:    after the gate, if the branch's diff against master touches any of: .ralph/ .claude/" "the dry run"
has "$out" "Task: **001 — Task 001-first**, described in \`docs/tasks/001-first.md\`" "the dry run's prompt"
has "$out" "This is the first attempt at this task." "the dry run's prompt"
has "$out" "agent:     fake-agent < prompt" "the dry run"
has "$out" "reviewer:  fake-agent < review prompt" "the dry run"
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
lacks "$(cat "$reviews/002/review.md")" "the report is in" "the kept report"
has "$(cat "$tmp/seq.log/002.review-prompt")" "- \`.claude/settings.json\`" "the review's prompt"
has "$(cat "$tmp/seq.log/002.review-prompt")" "Write the report to \`$reviews/002/" "the review's prompt"
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
  has "$out" "code could run with your next git command" "the loop after $act"
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
configure svc '.retries = 1 | .services = {wrap: "fake-svc --", env: ["FAKE_PORT", "FAKE_DIR", "NOT_SET"]} | .afterMerge = "env >\"$RALPH_TEST_LOG/after-merge.env\""'
out="$(ralph_in svc)" || fail "a task with services: $out"
seen="$(cat "$tmp/svc.log/001.env")"
has "$seen" "FAKE_PORT=" "the agent's environment with services"
lacks "$seen" "NOT_SET=" "the agent's environment with services"
[ "$(grep -c '^up 001' "$tmp/svc.log/services")" -eq 2 ] || fail "expected services for each of two attempts"
[ "$(grep -c '^down 001' "$tmp/svc.log/services")" -eq 2 ] || fail "services were not torn down after each attempt"
has "$(cat "$tmp/svc.log/001.prompt")" "started by the loop with \`fake-svc --\`" "the prompt with services"
[ -z "$(ls -A "$tmp/svc/.tmp" 2>/dev/null | grep svc || true)" ] || fail "the services' directory was left behind"
grep -q '^RALPH_AFTER=' "$tmp/svc.log/after-merge.env" || fail "afterMerge did not run with RALPH_AFTER"
! grep -q '^FAKE_PORT=' "$tmp/svc.log/after-merge.env" || fail "afterMerge got the attempt's service variables"
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

repo cmd "001-a|depends: -\ntouch: .ralph/notes.md" "002-b|depends: -\ntouch: .opencode/agent.md\nreview: silent" \
  "003-c|depends: -\ntouch: opencode.json\nreview: late"
printf 'You are the adversarial reviewer of {{TASK_ID}}.\n' >"$tmp/cmd/.ralph/review-prompt.md"
printf 'Compare {{BASE}} with {{HEAD}}.\n' >"$tmp/cmd/.ralph/review.md"
configure cmd '.agent = "FLAVOUR=\"two words\" fake-agent --worker \"$RALPH_TASK_ID\"" | .reviewAgent = "fake-agent --reviewer" | .env = {PARTITION: "_r{{TASK_ID}}"} | .reviewPrompt = ".ralph/review-prompt.md"'
out="$(ralph_in cmd)" || fail "the loop with a command string: $out"
[ "$(cat "$tmp/cmd.log/001.argv")" = "--worker 001" ] || fail "the agent's arguments: $(cat "$tmp/cmd.log/001.argv")"
grep -qx 'FLAVOUR=two words' "$tmp/cmd.log/001.env" || fail "the agent command's own variable did not reach it"
grep -qx 'PARTITION=_r001' "$tmp/cmd.log/001.env" || fail "env did not reach the agent"
[ "$(cat "$tmp/cmd.log/001.review-argv")" = "--reviewer" ] || fail "the reviewer's arguments: $(cat "$tmp/cmd.log/001.review-argv")"
has "$(cat "$tmp/cmd/.tmp/ralph/tasks/002/review.md")" "Verdict: review failed: the review wrote no report to .tmp/ralph/tasks/002/" "a review that wrote no report"
late="$(cat "$tmp/cmd/.tmp/ralph/tasks/003/review.md")"
has "$late" "Verdict: review failed: the review exited with status 3" "a review that failed after writing its report"
has "$late" "### major: task 003 weakens the gate" "a review that failed after writing its report"
custom="$(cat "$tmp/cmd.log/001.review-prompt")"
has "$custom" "Write the report to \`$tmp/cmd/.tmp/ralph/tasks/001/" "a custom review prompt without {{REPORT_FILE}}"
grep -qE '^Compare [0-9a-f]{40} with [0-9a-f]{40}\.$' <<<"$custom" || fail "the review instructions' placeholders: $custom"
lacks "$custom" "{{" "the review instructions"
[ "$(RALPH_REVIEW_AGENT=other ralph_in cmd --config | jq -r .reviewAgent)" = other ] || fail "RALPH_REVIEW_AGENT did not override reviewAgent"
[ "$(RALPH_AGENT=one ralph_in cmd --config --agent two | jq -r .agent)" = two ] || fail "--agent did not override RALPH_AGENT"
[ "$(RALPH_AGENT=one ralph_in cmd --config | jq -r .agent)" = one ] || fail "RALPH_AGENT did not override agent"
[ "$(ralph_in cmd --config --agent=solo | jq -r .agent)" = solo ] || fail "--agent=CMD was not read"
[ "$(ralph_in cmd --config --review-agent judge | jq -r .reviewAgent)" = judge ] || fail "--review-agent was not read"
[ "$(ralph_in cmd --config --review-agent=judge | jq -r .reviewAgent)" = judge ] || fail "--review-agent=CMD was not read"
status=0
out="$(ralph_in cmd --config --agent=)" || status=$?
[ "$status" -ne 0 ] || fail "an empty --agent= was accepted"
has "$out" "--agent needs a command" "an empty --agent="
configure cmd 'del(.agent, .reviewAgent)'
[ "$(ralph_in cmd --config --agent solo | jq -r .reviewAgent)" = solo ] || fail "the reviewer did not fall back to the agent"
status=0
out="$(ralph_in cmd)" || status=$?
[ "$status" -ne 0 ] || fail "the loop ran without an agent command"
has "$out" "no agent command is set" "the loop without an agent command"
ok "the agent and reviewer are shell commands from the config, RALPH_* or flags, with the prompt on stdin"

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
  cd "$tmp/stop" || exit 1
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
