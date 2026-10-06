---
name: ralph
description: The Ralph loop (the `ralph` command) — works through a repo's task files, one git worktree and branch per task, each done by a sandboxed unattended `claude -p`, gated, reviewed when it touches sensitive paths, and fast-forwarded into the target; runs tasks in parallel with --jobs. Load when running the loop, setting it up in a project (.ralph/config.json, task and decision files), writing or editing tasks, resuming, discarding or reading reviews, or when you are an iteration or reviewer inside it.
---

# The Ralph loop

`ralph` is on PATH (home-manager, `armanConfig.ai.ralph`). It runs in any git repository that has a `.ralph/config.json` with a `gate`, and task files on the target branch.

## The rules

1. **One task, one worktree, one branch.** The target branch only moves by fast-forward, after the gate passes.
2. **The task file is the contract.** If it is wrong or too big, fix the file, not the iteration.
3. **An iteration never guesses a decision.** It blocks with questions instead.
4. **Tasks share no files.** One file per task, one file per decision, the loop's state per task. That is what lets tasks run in parallel; a shared index or changelog that every task appends to makes them conflict.
5. **The loop never stops to ask about a merge.** A branch touching a sensitive path gets an adversarial review whose report waits for the user, and merges anyway.
6. **Iterations never touch git config or hooks.** The loop fingerprints `.git/config`, every `config.worktree`, `.git/info/attributes` and `.git/hooks` when it starts, and refuses to merge, and stops, if any of them changes. Its own git commands run with hooks and fsmonitor off.

## First: are you already sandboxed?

```
ls / >/dev/null 2>&1 && echo "not sandboxed" || echo "sandboxed"
```

`ralph` checks this itself (`sandbox.mode: auto`): when `ls /` is denied it is inside landrun, and iterations share that sandbox (`inherit`). Otherwise it wraps every agent, gate and review in `sandbox-ai` (`wrap`). Never nest a second sandbox inside the first; `--in-sandbox` forces `inherit`. Inside a shared sandbox, the worktrees must be under the directory the outer sandbox can write, which the default `.tmp/worktrees` is.

## Commands

```
ralph --status          every task, its status, and kept state ([failed], [blocked], [running], waits on)
ralph --dry-run         the next ready task, how it would run, and its rendered prompt; changes nothing
ralph --config          the effective configuration
ralph                   work through ready tasks until none are left
ralph -j 3              up to three tasks at a time
ralph --once            start at most one task
ralph --task 042        run this ready task, then stop
ralph --resume 042      continue a failed or blocked task in its kept worktree, then go on
ralph --discard 042     delete its worktree, branch and state, so it starts fresh
ralph --reviews         print the last run's reviews again
ralph --keep-going      keep starting tasks after one fails or blocks (default: stop starting new ones)
```

Exit status: 0 when everything started was merged, 1 when a task failed, 3 when one blocked and none failed, 130 when interrupted. One-run overrides: `RALPH_TARGET`, `RALPH_MODEL`, `RALPH_TIMEOUT`, `RALPH_RETRIES`, `RALPH_JOBS`, `RALPH_MAX_TASKS`, `RALPH_SANDBOX`, `RALPH_CONFIG`.

Several `ralph` processes can run in one repository at once: each claims a task under a lock, so two never take the same one.

## Setting up a project

1. `.ralph/config.json` with at least the gate:

   ```json
   { "gate": "nix flake check" }
   ```

   Every key, with an example for a project with its own Postgres per attempt, is in [references/config.md](references/config.md).
2. Ignore the loop's directories: add `.tmp/` to `.gitignore` (or whatever `worktreeDir` and `stateDir` name).
3. Write tasks in `docs/tasks/` (see "Writing tasks") and decisions as one file each in `docs/decisions/`.
4. Optional: `.ralph/instructions.md` is added to every iteration's prompt, and `.ralph/review.md` to every review's: put the project's specifics there (which skills to read, how to run tests, what never to touch, reference directories). They take the same `{{…}}` placeholders as the prompts.
5. **Commit all of it.** The loop reads task files from the target branch, not the working tree, because that is what each new worktree starts from.

## What one task goes through

1. **Pick**: the lowest id (version order) with `status: todo` on the target, whose `depends` are all `done` there, with no kept state and not claimed by another worker or process.
2. **Worktree**: `git worktree add -b ralph/<id>-<slug> <worktreeDir>/ralph-<id>-<slug> <target>`, then `setup` in it (outside the sandbox: copying build caches, e.g. `wt step copy-ignored`).
3. **Services**: when `services.wrap` is set, the loop starts it (outside the sandbox, in the worktree) around a process that holds it open, and passes the variables named in `services.env` to the agent, the gate and the review. It is torn down when the attempt ends; a retry gets a new one. This is how a project gives every attempt its own database (`with-pg-db --`).
4. **Agent**: `claude -p --dangerously-skip-permissions --settings <settings> --output-format stream-json --verbose`, the rendered prompt on stdin, under `timeout`, in the sandbox, in the worktree. Commit signing is switched off for it through `GIT_CONFIG_*`, since the sandbox can't reach gpg.
5. **Checks**: the agent exited 0, the worktree is clean, there is at least one commit, and the task file says `done` (or `blocked`). Then the gate, in the sandbox.
6. **Review**: if the branch's diff touches `sensitivePaths`, one more `claude -p` with the review prompt; its last message becomes `<stateDir>/tasks/<id>/review.md`. A review that changes the worktree is reset. The merge goes ahead either way.
7. **Merge**, under a lock shared by every worker: if the target moved since the branch started, rebase onto it and run the gate again; then fast-forward the target where it is checked out (its tracked files must be clean), or move the ref with a compare-and-swap if it isn't checked out anywhere. Then `afterMerge` in that checkout, and the worktree and branch are deleted.
8. **Failure**: up to `retries` more attempts in the same worktree, with the failure (gate output, timeout, dirty tree, rebase conflict) in the prompt. Then the task's state is kept and the worktree stays.

Logs, prompts and reviews live in `<stateDir>/tasks/<id>/`, named `<run>.<attempt>.<what>`: `agent.jsonl`, `prompt.md`, `gate.log`, `gate-rebased.log`, `services.log`, `review.jsonl`, `merge.log`.

## When a task blocks or fails

- **Blocked**: the iteration wrote `## Open questions` and set `status: blocked`. Answer under `## Answers` in the worktree's copy of the task file (the path is printed) and commit it there, or settle it as a decision on the target. Then `ralph --resume <id>`: it rebases the worktree onto the target, and the agent reads `## Answers` and amends its commit.
- **Failed**: look at the logs and the kept worktree, then `ralph --resume <id>`, or `ralph --discard <id>`, fix the task file on the target, and run again.
- **Git config or hooks changed**: the run stops and nothing more merges. Undo the change in `.git/`, then resume or discard.
- **Interrupted** (Ctrl-C): agents and services are stopped, the task is kept as failed with reason `interrupted`; resume it.

## Writing tasks

One file per task: `<tasksDir>/<id>-<slug>.md`. The id is everything before the first `-`; ids sort in version order, so space them (`010`, `020`) to leave room. The frontmatter is plain `key: value` lines:

```markdown
---
id: 042
title: Event store on Postgres
status: todo
depends: 010, 020
skills: event-sourcing, testing
---

# 042 — Event store on Postgres

## Goal
## Context
## Scope
## Acceptance criteria
## Verification
## Outcome
```

- `status`: `todo` · `done` · `blocked`. Only the iteration doing the task changes it, in its own commit.
- `depends`: ids that must be `done` on the target first, or `-`. Tasks without a dependency between them may run at the same time, so a task that needs another's output must depend on it.
- `skills`: `.claude/skills/<name>` the iteration reads first.
- Body: **Context** links docs, decisions and the files that show the pattern; **Scope** says what is in and what is out (and which task does it); **Acceptance criteria** are testable checkboxes, each proved by a test or a command; **Outcome** is filled in by the iteration.

A good task is one concern, about an hour of work, ten or fewer acceptance criteria, names everything it assumes and puts the task that creates it in `depends`. Tasks that run in parallel shouldn't edit the same lines: give them a dependency, or accept a rebase conflict that a retry resolves.

Never hide a product decision inside a task. Ask the user, record the decision as its own file, then write the task.

## Inside an iteration

The prompt says all of this; these are the parts that bite:

- **`git add` new files before `nix build` or `nix run`.** A flake can't see untracked files.
- **One commit**, in the repository's style, with no trailers. Amend it on a retry or a resume.
- **Stay in your worktree and your task file.** Other iterations may be running beside you. Record follow-ups in `## Outcome`, and don't do them.
- **Decisions go in a new file** `<decisionsDir>/<id>-<slug>.md` with `status: provisional`, never appended to a shared list.
- **Never change git config, `core.hooksPath` or `.git/hooks`.** The loop stops without merging.
- **The services are yours alone.** Never start, stop or reset them; run a second instance under the same wrapper if the task needs one.
