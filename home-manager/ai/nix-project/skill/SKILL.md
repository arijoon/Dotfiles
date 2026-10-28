---
name: nix-project
description: Initialise a repo with a Nix project setup — a flake whose devshell, tasks (`task <env> <name>`), apps, per-env config (`nix/envs/<env>`), sops/age secrets declared per task, and `task check` gate are typed Nix modules under `nix/`. Load when the user asks to set up, scaffold or bootstrap a project with this nix/tasks/secrets/flake setup, or to add an env, a restricted env, a debug secrets file, a task, a gate or a language/app module to a project built from it.
---

# Nix project setup

`nix-project-init` is on PATH (home-manager, `armanConfig.ai.nixProject`). It copies the whole framework, so **never write the core modules by hand**; write only the project's own modules.

## Initialise

```
nix-project-init [--name NAME] [--no-nix] [DIR]     DIR defaults to .; NAME to its basename
```

It `git init`s if needed and copies, never overwriting:

```
flake.nix                    envs = every directory under nix/envs/ except shared/; dev is the default
nix/default.nix              imports the core modules; add the project's modules here
nix/devshell.nix             devshell.{packages,env,shellHook}; options.env, the env attrset
nix/tasks.nix                tasks.<name>, the `task` runner, run-any
nix/apps.nix                 apps.<name>.{package,actions}, the env loader
nix/check.nix                checks.steps -> `task check`
nix/fmt.nix                  treefmt; formatting.formatters; fmt, fmt-check (a gate)
nix/run.nix                  services.run.processes -> `task run` (process-compose)
nix/secrets.nix              sops files, keys, loader, secrets/shared-secrets/debug-secrets/sops-config, secrets-check (a gate)
nix/envs/{dev,shared}/       dev is unrestricted, key in .secrets/dev.key
.envrc .gitignore .prettierrc treefmt.toml
CLAUDE.md                    "Working in this repo" section
.claude/skills/local-dev/    the project's skill: tasks, env, secrets
```

Then it makes `.secrets/dev.key`, puts its public key in `nix/envs/dev/default.nix`, `git add`s what it created, and runs `nix run .#p.dev.tasks.sops-config` (writes `.sops.yaml`, creates `flake.lock`). It commits nothing.

A file it **kept** is printed with its template's store path: merge by hand (an existing `CLAUDE.md` gets the template's section; an existing `flake.nix` needs its outputs folded in). Inside landrun, flake refs through the registry (`nix run nixpkgs#…`) fail with `opening file "/"`; the project's own `nix run .#…` works. For a tool the project doesn't carry, use a store path or a task.

Verify with `nix run .#p.dev.tasks.check` (fmt-check, secrets-check) and `nix run .#task -- --list`.

## Adding the project's modules

One module per concern in `nix/`, imported from `nix/default.nix`, `git add`ed. Patterns, copy from the examples beside this file:

- `examples/nodejs.nix` — a language module: `languages.<x>.package` options, pushed onto `devshell.packages`.
- `examples/web.nix` — a component module: `options.env.<KEY>` with defaults, `apps.<name>.actions.build`, `tasks.<name>` with their own `runtimeInputs`, a process for `task run`, a gate via `checks.steps = lib.mkOrder 1600 [ "<task>" ]`.

Rules: a task carries everything it needs in `runtimeInputs`; behaviour comes from env keys, never the env's name; an env's own values only in `nix/envs/<env>/default.nix`; a tool a formatter calls goes in `formatting.formatters` and its formatter in `treefmt.toml`; a long-lived process goes in `services.run.processes.<proc> = "<task>"`; a task whose script embeds a generated file sets `fresh = true`.

## Secrets

A task declares keys: `tasks.<name>.secrets.required = [ "API_KEY" ];` (or `optional`, `own`, `debug`). Fill them with `task secrets edit`; `secrets.generate.<KEY> = <bytes>;` in an env makes `task <env> secrets init` add random hex.

**Add a restricted env** (its key outside the repo; sessions can't decrypt it, so the user runs its commands):

1. The user runs `age-keygen -o ~/.config/sops/age/<env>.key` and gives you `age-keygen -y` of it.
2. `nix/envs/<env>/default.nix`: `imports = [ ../shared ]; secrets = { restricted = true; recipient = "age1…"; }; env = { … };`, then `git add` it.
3. `nix run .#p.dev.tasks.sops-config`. The shared file's rule appears with the first restricted env, and dev's file is now encrypted to that env's key too: if it exists, re-key it with dev's key: `SOPS_AGE_KEY_FILE=.secrets/dev.key sops updatekeys -y nix/envs/dev/secrets.yaml` (sops is in the devshell), or `secrets-check` fails.

**Add an unrestricted env**: as above with `restricted = false;` and its key at `.secrets/<env>.key` (`age-keygen -o`).

**Add a debug file** to an env (a second key, decrypting only `debug-secrets.yaml`, that sessions may hold): `age-keygen -o .secrets/<env>-debug.key`, its public key as `secrets.debugRecipient`, optionally `secrets.debugGenerate.<KEY> = <bytes>;`, `sops-config`, then `task <env> debug-secrets init | edit`. A task reads it with `secrets.debug = [ "KEY" ];` plus `required`/`optional`.

Name keys `<env>.key`, never `keys.txt` (sops loads that for every command). Tell the user to back up each key off the machine.
