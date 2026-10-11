# opencode as the ralph agent

```
OPENCODE_CONFIG_CONTENT='{"permission":"allow","share":"disabled","autoupdate":false}' opencode run
```

Inside `.ralph/config.json` the quotes need escaping:

```json
"agent": "OPENCODE_CONFIG_CONTENT='{\"permission\":\"allow\",\"share\":\"disabled\",\"autoupdate\":false}' opencode run"
```

- `opencode run` appends stdin to its message when stdin isn't a terminal, so the prompt on stdin works with no message argument.
- **`"permission": "allow"` is required.** `opencode run` answers every permission it would ask for with a rejection. Without it, the iteration can't touch anything outside the worktree, and the reviewer can't write its report, which lives in ralph's state dir.
- `"share": "disabled"` keeps a project's `share: auto` from uploading the session. `"autoupdate": false` stops it updating itself mid-run.
- `OPENCODE_CONFIG_CONTENT` is merged after the global config, `OPENCODE_CONFIG`, the project's `opencode.json` and `.opencode/` configs, so their top-level `permission` can't undo it.
- Optional: `--model provider/model`, `--variant high` (provider-specific reasoning effort), `--agent build`.
- For the local llama-server through the home-manager wrapper, put the variable in the command: `LLAMA_SERVER=127.0.0.1:5001 opencode run`.

## As the reviewer

The same command works, as long as `"permission": "allow"` is in it: the report file is outside the worktree. It runs in the worktree of the branch it reviews, so opencode loads that branch's `opencode.json` and `.opencode/`. `OPENCODE_CONFIG_CONTENT` is merged after them and wins on the keys it sets, but plugins from both are kept and the branch's MCP servers still start. A branch that changed those shapes its own review.

## It exits 0 when the model call fails

If the provider is down or rejects the request, `opencode run` prints the error and still exits 0. ralph still catches it: an iteration that made no commit, or left the task file not `done`, fails the attempt, and a reviewer that wrote no report is recorded as a failed review. The error itself is in `agent.log` or `review.log`.

## Logs

Without `--format`, opencode prints each text part as it finishes, so `agent.log` holds the agent's commentary for the whole run. `--format json` writes one JSON event per line (`text`, `tool_use`, `step_start`, `step_finish`, `error`) instead.

## Sandboxing

`sandbox-ai` grants opencode's data, state and cache directories (`~/.local/share/opencode`, `~/.local/state/opencode`, `~/.cache/opencode`) read-write and `~/.config/opencode` read-only; opencode skips installing plugin dependencies when its config dir isn't writable. `sandbox-ai` forwards only a fixed set of variables. When the whole loop runs inside it, `LLAMA_SERVER=… opencode run` works as written. When only the agent command is wrapped, set them after the sandbox with `env`: `sandbox-ai -- env LLAMA_SERVER=… OPENCODE_CONFIG_CONTENT='…' opencode run`.
