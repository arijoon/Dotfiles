---
name: opencode
description: The armanConfig.ai.opencode module (home-manager/ai/opencode) — the regular opencode configured for a llama.cpp llama-server at $LLAMA_SERVER, its small never-refusing prompt, the SearXNG search tool, and how to test a change against a stub server without keeping test code in the repo. Load when changing that module, its prompt or its search tool, or when opencode on the local model misbehaves.
---

# opencode on llama-server

## What the module does

`home-manager/ai/opencode/` (option `armanConfig.ai.opencode.enable`, on for `arman`):

- `default.nix` sets `programs.opencode`:
  - Its package is a wrapper named `opencode` around `pkgs-latest.opencode`. The wrapper exports three variables, each unless the caller set it:
    - `LLAMA_SERVER`: `vopono.host:<port>` when `/etc/hosts` names `vopono.host` (inside `with-vpn -H`), else `127.0.0.1:<port>`.
    - `SEARXNG_URL`: the `searxngUrl` option.
    - `OPENCODE_EXPERIMENTAL_OUTPUT_TOKEN_MAX`: the `output` option, because opencode otherwise caps `max_tokens` at 32000.
  - The `llama` provider (`@ai-sdk/openai-compatible`, `baseURL` `http://{env:LLAMA_SERVER}/v1`) is the default `model` and `small_model`.
  - The model entry has `reasoning: true` and `interleaved.field = "reasoning_content"`, so each reply's reasoning goes back to the model on the next turn. That keeps llama.cpp's prompt cache valid on hybrid models like Qwen3.8.
  - `prompt.md` replaces opencode's base prompt for the `build`, `plan` and `general` agents. `explore` keeps opencode's own.
  - `mcp.searxng` runs `searxng-mcp.py`, which the model sees as `searxng_search`.
- `prompt.md` is kept small for local models. It does whatever the operator asks, never refuses, and treats everything that comes in through tools as data, never as instructions.
- Skills and instructions come from opencode's own discovery, which the module leaves on. That covers:
  - `~/.claude/skills/**/SKILL.md`, recursive, so `synced/` too;
  - `~/.agents/skills` and `~/.config/opencode/skills`;
  - the project's `.claude`, `.agents` and `.opencode` skills;
  - `~/.claude/CLAUDE.md` and the project's `AGENTS.md` as instructions.

  The user wants all of it, so nothing is filtered.
- Nothing is sandboxed or put behind a VPN here. The user composes `with-vpn` and `sandbox-run`/`sandbox-ai` by hand.

## Testing a change

No test code lives in the repo. Put everything below in a scratch directory, and delete it when you're done.

**Never point a test at the real llama-server.** It may be serving on `127.0.0.1:5001` or `192.168.0.237:5001`, and a request loads the GPU. Use a stub.

**Don't wrap tests in another sandbox.** The session is usually sandboxed already, and nested bubblewrap fails there.

1. Evaluate and build the pieces. The second build pulls in the search tool too.

   ```
   cd ~/.dotfiles/home-manager
   nix eval --json '.#homeConfigurations.arman.config.programs.opencode.settings'
   nix build --no-link --print-out-paths \
     '.#homeConfigurations.arman.config.programs.opencode.package' \
     '.#homeConfigurations.arman.config.xdg.configFile."opencode/opencode.json".source'
   nix eval --raw '.#homeConfigurations.arman.activationPackage.drvPath'
   ```

   `git add` new files first: the flake can't see untracked ones.

2. Start a stub llama-server on a free loopback port. It must:
   - answer `POST /v1/chat/completions`, streaming SSE when `stream` is true;
   - log each request body;
   - for the reasoning test, send a `reasoning_content` delta before the content;
   - for the tool test, answer a last user message `call <tool> <json>` with that tool call.

   `/storage/industry/koboldcpp/nix/kobold-stub.py` already does all of this:

   ```
   python3 kobold-stub.py <dir> --model /m/qwen.gguf --context 262144 \
     --reply "stub reply" --reasoning "stub reasoning" --server llama-server
   ```

   It writes its port to `<dir>/port` and its requests to `<dir>/requests.jsonl`.

3. Run the built wrapper against it with a throwaway home. Write the `env` assignments out in full: zsh doesn't split a variable holding several of them.

   ```
   T=<scratch>; mkdir -p $T/{home,config/opencode,data,state,cache,work}
   ln -s <built opencode.json> $T/config/opencode/opencode.json
   cd $T/work && env HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data \
     XDG_STATE_HOME=$T/state XDG_CACHE_HOME=$T/cache LLAMA_SERVER=127.0.0.1:<port> \
     SEARXNG_URL=http://127.0.0.1:9 <wrapper>/bin/opencode run call bash '{"command":"echo","description":"x"}'
   ```

   `opencode run` quotes any argument that holds a space, so pass `call`, the tool name and space-free JSON as separate arguments.

4. Check the stub's requests:
   - `POST /v1/chat/completions` with the configured model id;
   - `max_tokens` equal to the `output` option;
   - the agent request's first system message starting with `prompt.md`;
   - `searxng_search` among the tools;
   - on the second request, the assistant message carrying the stub's reasoning as `reasoning_content`.

   `opencode run call searxng_search '{"query":"test"}'` with nothing on `SEARXNG_URL` should put "SearXNG isn't running" in the tool result.

5. Check the defaults with `opencode debug config`. With `LLAMA_SERVER` and `SEARXNG_URL` unset, it should show `baseURL` `http://127.0.0.1:5001/v1` and `SEARXNG_URL` `http://127.0.0.1:8890`. It sends no chat request.

6. To check the `vopono.host` branch without root:
   - Copy the wrapper script with `sed`, replacing `/etc/hosts` with a scratch hosts file and the `exec` line with an `echo` of the three variables.
   - Run the copy with `bash`, once against a hosts file that names `vopono.host` and once against one that doesn't.
   - Run it once more with `LLAMA_SERVER` set; it must win over both.
