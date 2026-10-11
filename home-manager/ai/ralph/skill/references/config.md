# .ralph/config.json

Read from the main checkout's working tree (or `RALPH_CONFIG`). Every key is optional except `gate` and `agent` (which `--agent` or `RALPH_AGENT` can give instead). Paths are relative to the main checkout unless absolute or starting with `~/`.

| Key | Default | Meaning |
| --- | --- | --- |
| `gate` | — | Shell command (run with `bash -c` in the worktree) that must exit 0 before a merge. `"true"` merges without one. |
| `agent` | — | Shell command that does a task: run with `bash -c` in the worktree, the prompt on stdin. `--agent`, then `RALPH_AGENT`, override it. See [claude.md](claude.md) and [opencode.md](opencode.md). |
| `reviewAgent` | `agent` | Shell command that reviews a sensitive branch, the same way. `--review-agent`, then `RALPH_REVIEW_AGENT`, override it. |
| `target` | the main checkout's branch | Branch every task starts from and is merged into. |
| `tasksDir` | `docs/tasks` | Task files, read from the target branch. |
| `decisionsDir` | `docs/decisions` | Where iterations add one file per decision. |
| `worktreeDir` | `.tmp/worktrees` | Task worktrees. Keep it inside the checkout when the loop runs in a sandbox that can only write there. |
| `stateDir` | `.tmp/ralph` | Locks, per-task state and logs, per-run records. |
| `branchPrefix` | `ralph/` | Task branches are `<prefix><id>-<slug>`. |
| `timeout` | `90m` | Limit for each agent run, gate, review and hook (`timeout` syntax). |
| `retries` | `1` | Further attempts after a failed one, in the same worktree. |
| `jobs` | `1` | Tasks worked on at once (`--jobs` overrides). |
| `maxTasks` | `0` | Tasks started per run; 0 means no limit. |
| `keepGoing` | `false` | Keep starting tasks after one fails or blocks. |
| `prompt` | built in | Replaces the iteration prompt template. |
| `instructions` | `.ralph/instructions.md` if it exists | Added to the iteration prompt at `{{INSTRUCTIONS}}`. |
| `reviewPrompt` | built in | Replaces the review prompt template. |
| `reviewInstructions` | `.ralph/review.md` if it exists | Added to the review prompt. |
| `sensitivePaths` | `.ralph/ .claude/ .mcp.json .opencode/ opencode.json opencode.jsonc .envrc .github/ .config/wt.toml` | Git pathspecs; a branch whose diff touches one is reviewed before merging. `[]` turns reviews off. |
| `setup` | — | Shell command run in a new worktree before the first attempt. |
| `afterMerge` | — | Shell command run where the target is checked out after each merge, with `RALPH_BEFORE` and `RALPH_AFTER` set. A failure is logged and ignored. |
| `services.wrap` | — | Command prefix that starts per-attempt services and runs the command after it, like `with-pg-db --`. Runs in the worktree. |
| `services.env` | `[]` | Variables the wrapper sets that the agent, gate and review get. |
| `services.startTimeout` | `600` | Seconds to wait for the wrapper to start its command. |
| `env` | `{}` | Extra variables for the agent, gate, review and hooks. Values may use `{{TASK_ID}}`, `{{BRANCH}}`, `{{WORKTREE}}`, `{{ROOT}}`. |
| `unsetEnv` | `[]` | Variables removed from everything the loop starts, e.g. devshell variables that point at the main checkout. |

Every command the loop starts also gets `RALPH_TASK_ID`, `RALPH_BRANCH`, `RALPH_TARGET`, `RALPH_WORKTREE` and `RALPH_ROOT`, and the project's PATH (the loop's own tools are not prepended to it). A sandbox around the agent command alone passes on only the variables it is told to forward with `--env`, so these, `env` and `services.env` reach the agent only if forwarded.

## Prompt placeholders

Iteration and review prompts: `{{TASK_ID}}`, `{{TASK_TITLE}}`, `{{TASK_FILE}}`, `{{TASKS_DIR}}`, `{{DECISIONS_DIR}}`, `{{BRANCH}}`, `{{TARGET}}`, `{{TIMEOUT}}`, `{{GATE}}`, `{{SERVICES}}` (a sentence about the attempt's services). Iteration prompt only: `{{ATTEMPT}}`, `{{CONTEXT}}` (the retry, resume or conflict note). Review prompt only: `{{BASE}}`, `{{HEAD}}`, `{{PATHS}}`, `{{REPORT_FILE}}` (where the reviewer writes its report). An instruction file takes the placeholders of the prompt it is added to. When a custom template leaves one out, `{{INSTRUCTIONS}}`, `{{CONTEXT}}` and `{{PATHS}}` are appended, and so is a line telling the reviewer to write its report to `{{REPORT_FILE}}`.

## Example: a Nix project with a Postgres per attempt

```json
{
  "target": "master",
  "gate": "nix run .#p.dev.tasks.check",
  "agent": "claude -p --dangerously-skip-permissions --settings \"$RALPH_ROOT/.ralph/claude-settings.json\" --effort high",
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
  "afterMerge": "git diff --quiet \"$RALPH_BEFORE\" \"$RALPH_AFTER\" -- core/mix.exs core/mix.lock || nix run .#p.dev.tasks.deps",
  "sensitivePaths": ["nix/", "flake.*", ".envrc", ".sops.yaml", ".config/wt.toml", ".claude/", ".ralph/", "infra/"]
}
```

Started from the main checkout as `sandbox-ai -l --rw ~/.cache --rw ~/.local/share/pnpm --ro ../property-indexer -- ralph`, so the loop and everything it runs share one sandbox that can also write the build caches and read the reference repository. `.ralph/claude-settings.json` holds `{"attribution": {"commit": "", "pr": ""}}` (see [claude.md](claude.md)).

With `.ralph/instructions.md` holding what only that project needs: which skills and docs every task reads first, that `task` on PATH comes from the target so a task added on the branch runs as `nix run .#p.dev.tasks.<name>`, and that reference code lives in `../property-indexer`.
