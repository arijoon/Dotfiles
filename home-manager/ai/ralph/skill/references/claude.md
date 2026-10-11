# Claude Code as the ralph agent

```
claude -p --dangerously-skip-permissions --settings "$RALPH_ROOT/.ralph/claude-settings.json"
```

- `-p` reads the prompt from stdin and exits when the agent is done; its exit status is what ralph sees.
- `--dangerously-skip-permissions`: nobody is there to approve a tool call. The sandbox around the loop or the command is the boundary (see "Sandboxing is yours" in SKILL.md).
- `--settings` takes a file or inline JSON. `{"attribution": {"commit": "", "pr": ""}}` stops Claude Code adding its `Co-Authored-By` trailer, which the iteration prompt forbids. ralph sets `RALPH_ROOT` to the main checkout and `bash -c` expands it, so `"$RALPH_ROOT/.ralph/claude-settings.json"` is always the main checkout's copy. A relative path would resolve in the task's worktree, which is the branch's own copy, and a branch under review could have changed it. Inline, inside the config's JSON string: `--settings '{\"attribution\":{\"commit\":\"\",\"pr\":\"\"}}'`.
- Optional: `--model opus`, `--effort high`, `--max-budget-usd 20`.

## Logs

Plain `-p` writes only the final message, so `agent.log` stays readable, and a failed attempt's "end of its output" is the agent's own last words. `--output-format stream-json --verbose` writes the whole transcript as JSON lines instead: better for digging into a run, worse to read in the failure note.

## As the reviewer

The same command works. The review prompt asks it to write the report to a file in ralph's state dir, outside the worktree; `--dangerously-skip-permissions` covers that. Its final message is ignored.

It runs in the worktree of the branch it reviews, so Claude Code loads that branch's `.claude/settings.json` (hooks included) and `CLAUDE.md`, and sees its `.mcp.json`. A branch that changed them shapes its own review; that is why the settings path above goes through `$RALPH_ROOT`.

## Sandboxing

`sandbox-ai` already grants `~/.claude`, `~/.claude.json` and `~/.cache/claude-cli-nodejs` and forwards `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN`.
