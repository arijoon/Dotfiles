---
name: local-dev
description: Running anything locally — the task dispatcher, the env attrset, envs under nix/envs/, sops secrets and which task gets which key, and the check gate. Load before running a command, adding a task, an env key or a secret, or debugging why config did not reach a process.
---

# Running things locally

## The rules

1. **Every command goes through a task.** Never `nix develop --command` with environment variables passed by hand.
2. **Config comes from the `env` attrset.** Each key is declared as an option under `options.env`, with a default, by the module that owns the component, and overridden in `nix/envs/<env>/default.nix`. Never invent a value at the call site, never branch on the env's name.
3. **`task` is a cache.** Editing a task's command, or adding a task, needs the devshell re-entered (`direnv reload`). `nix run .#p.<env>.tasks.<name>` is always current, and so is a task with `fresh = true`.
4. **New `.nix` files must be `git add`ed** before Nix can see them.
5. **A task carries its own tools** in `runtimeInputs`; it runs outside the devshell as often as in it.

## Tasks

```
task --list                         the authoritative list, generated from the modules
task <name> [args]                  under dev
task <env> <name> [args]            the same task under another env: nix run .#p.<env>.tasks.<name> -- [args]
task run-any <cmd>                  anything, with the env loaded, at the repo root
task check                          every gate in checks.steps, in order
task fmt | fmt-check                treefmt
task run                            process-compose over services.run.processes (once any are set)
```

A module adds a task as `tasks.<name> = { description; runtimeInputs; command; secrets.required/optional; fresh; }`, a gate by appending the task's name to `checks.steps`, and a deployable as `apps.<name> = { package; actions.<action>; }`, run as `nix run .#p.<env>.<name>.<action>`.

## Secrets

```
nix/envs/<env>/secrets.yaml         the env's secrets: every value age-encrypted by sops, committed
nix/envs/shared/secrets.yaml        what every restricted env shares (exists once one env is restricted)
nix/envs/<env>/debug-secrets.yaml   only when the env sets secrets.debugRecipient
.sops.yaml                          generated: task sops-config
.secrets/<env>.key                  an unrestricted env's age key (dev's), gitignored; sessions may read it
~/.config/sops/age/<env>.key        a restricted env's key, outside the repo and every sandbox: the user runs its commands
```

```
task [<env>] secrets edit | show-keys | init       init adds the keys in secrets.generate the file lacks
task <env> shared-secrets edit | show-keys         with a restricted env's key
task [<env>] debug-secrets edit | show-keys | init with the debug key alone
task sops-config                                   rewrite .sops.yaml from the env modules
```

A task declares the keys it needs: `secrets.required` (missing stops it) and `secrets.optional`; `secrets.own` takes a key from the env's own file only, `secrets.debug` from its debug file. Only for that task does the loader decrypt them, into its process alone, skipping any the caller already set. An env can add a declaration for one env only in its own module (`tasks.<name>.secrets.optional = [ … ];`).

`secrets-check` (in `task check`) fails on a plaintext value, a secrets file no rule covers, a file encrypted to other recipients than its rule's, or a stale `.sops.yaml`.
