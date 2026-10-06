# .ralph/config.json

Read from the main checkout's working tree (or `RALPH_CONFIG`). Every key is optional except `gate`. Paths are relative to the main checkout unless absolute or starting with `~/`.

| Key | Default | Meaning |
| --- | --- | --- |
| `gate` | — | Shell command (run with `bash -c` in the worktree, in the sandbox) that must exit 0 before a merge. `"true"` merges without one. |
| `target` | the main checkout's branch | Branch every task starts from and is merged into. |
| `tasksDir` | `docs/tasks` | Task files, read from the target branch. |
| `decisionsDir` | `docs/decisions` | Where iterations add one file per decision. |
| `worktreeDir` | `.tmp/worktrees` | Task worktrees. Keep it inside the checkout when the loop runs in a shared sandbox. |
| `stateDir` | `.tmp/ralph` | Locks, per-task state and logs, per-run records. |
| `branchPrefix` | `ralph/` | Task branches are `<prefix><id>-<slug>`. |
| `timeout` | `90m` | Limit for each agent run, gate, review and hook (`timeout` syntax). |
| `retries` | `1` | Further attempts after a failed one, in the same worktree. |
| `jobs` | `1` | Tasks worked on at once (`--jobs` overrides). |
| `maxTasks` | `0` | Tasks started per run; 0 means no limit. |
| `keepGoing` | `false` | Keep starting tasks after one fails or blocks. |
| `model` | claude's default | Passed as `--model`. |
| `agentArgs` | `[]` | Extra `claude` arguments, e.g. `["--effort", "high", "--max-budget-usd", "20"]`. |
| `claude` | `claude` | The agent command. |
| `settings` | `{"attribution": {"commit": "", "pr": ""}}` | Settings for every `claude -p`: an object, or the path of a JSON file. |
| `prompt` | built in | Replaces the iteration prompt template. |
| `instructions` | `.ralph/instructions.md` if it exists | Added to the iteration prompt at `{{INSTRUCTIONS}}`. |
| `reviewPrompt` | built in | Replaces the review prompt template. |
| `reviewInstructions` | `.ralph/review.md` if it exists | Added to the review prompt. |
| `sensitivePaths` | `.ralph/ .claude/ .mcp.json .envrc .github/ .config/wt.toml` | Git pathspecs; a branch whose diff touches one is reviewed before merging. `[]` turns reviews off. |
| `setup` | — | Shell command run in a new worktree before the first attempt, outside the sandbox. |
| `afterMerge` | — | Shell command run where the target is checked out after each merge, outside the sandbox, with `RALPH_BEFORE` and `RALPH_AFTER` set. A failure is logged and ignored. |
| `services.wrap` | — | Command prefix that starts per-attempt services and runs the command after it, like `with-pg-db --`. Runs outside the sandbox, in the worktree. |
| `services.env` | `[]` | Variables the wrapper sets that the agent, gate and review get. |
| `services.startTimeout` | `600` | Seconds to wait for the wrapper to start its command. |
| `env` | `{}` | Extra variables for the agent, gate, review and hooks. Values may use `{{TASK_ID}}`, `{{BRANCH}}`, `{{WORKTREE}}`, `{{ROOT}}`. |
| `unsetEnv` | `[]` | Variables removed from everything the loop starts, e.g. devshell variables that point at the main checkout. |
| `sandbox.mode` | `auto` | `auto` (inherit when `ls /` is denied, else wrap), `wrap`, `inherit` or `none`. |
| `sandbox.command` | `sandbox-ai` | A `sandbox-run` preset; called as `<command> -l <landrun args> -- <cmd>`. |
| `sandbox.rw` | `["~/.cache/nix"]` | Extra read-write paths in wrap mode. The git common dir is always added; missing paths are skipped. |
| `sandbox.ro`, `sandbox.rox` | `[]` | Extra read-only (and executable) paths in wrap mode, e.g. reference repositories tasks point at. |

Every command the loop starts also gets `RALPH_TASK_ID`, `RALPH_BRANCH`, `RALPH_TARGET`, `RALPH_WORKTREE` and `RALPH_ROOT`, and the project's PATH (the loop's own tools are not prepended to it).

## Prompt placeholders

Iteration and review prompts, and the instruction files: `{{TASK_ID}}`, `{{TASK_TITLE}}`, `{{TASK_FILE}}`, `{{TASKS_DIR}}`, `{{DECISIONS_DIR}}`, `{{BRANCH}}`, `{{TARGET}}`, `{{TIMEOUT}}`, `{{GATE}}`, `{{SERVICES}}` (a sentence about the attempt's services). Iteration prompt only: `{{ATTEMPT}}`, `{{CONTEXT}}` (the retry, resume or conflict note). Review prompt only: `{{BASE}}`, `{{HEAD}}`, `{{PATHS}}`. `{{INSTRUCTIONS}}` and `{{CONTEXT}}` are appended when a custom template leaves them out.

## Example: a Nix project with a Postgres per attempt

```json
{
  "target": "master",
  "gate": "nix run .#p.dev.tasks.check",
  "timeout": "90m",
  "retries": 1,
  "jobs": 2,
  "setup": "wt step copy-ignored --require-include",
  "services": {
    "wrap": "with-pg-db --",
    "env": ["PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "DIRECT_DATABASE_URL", "DATABASE_URL"]
  },
  "env": { "MIX_TEST_PARTITION": "_r{{TASK_ID}}" },
  "unsetEnv": ["PRJ_ROOT", "MIX_HOME", "HEX_HOME"],
  "sandbox": {
    "rw": ["~/.cache", "~/.local/share/pnpm"],
    "ro": ["../property-indexer"]
  },
  "afterMerge": "git diff --quiet \"$RALPH_BEFORE\" \"$RALPH_AFTER\" -- core/mix.exs core/mix.lock || nix run .#p.dev.tasks.deps",
  "sensitivePaths": ["nix/", "flake.*", ".envrc", ".sops.yaml", ".config/wt.toml", ".claude/", ".ralph/", "infra/"]
}
```

With `.ralph/instructions.md` holding what only that project needs: which skills and docs every task reads first, that `task` on PATH comes from the target so a task added on the branch runs as `nix run .#p.dev.tasks.<name>`, and that reference code lives in `../property-indexer`.
