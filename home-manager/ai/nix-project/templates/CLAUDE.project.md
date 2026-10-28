# @PROJECT@

## Working in this repo

`direnv allow` once, then the devshell loads (`nix develop` otherwise).

The devshell is a set of Nix modules under `nix/`, one per concern, each exposing typed options. Add a tool by editing the module it belongs to. **Tasks are Nix, not a justfile:**

```
task --list                        the authoritative list
task [<env>] <name> [args]         fast path; cached until the devshell is re-entered, except fresh tasks
nix run .#p.dev.tasks.<name> -- …  always current (use it for tasks added or changed since you entered)
```

- Environments are the directories under `nix/envs/` (except `shared/`). They set keys in the `env` attrset, and every key is an option declared, with a default, by the module that owns the component. Tasks and apps get that env through the loader; `nix develop` alone does not.
- **Behaviour comes from named config keys, never from the environment's name.**
- **Secrets are sops files beside the env modules** (`nix/envs/<env>/secrets.yaml`), age-encrypted to `.sops.yaml`'s recipients, which `task sops-config` generates from the env modules. A task gets only the keys it declares in `secrets.required` / `secrets.optional`.
- `task check` runs every registered gate (`checks.steps`).
- New `.nix` files must be `git add`ed before Nix sees them.

Load the `local-dev` skill before running anything.
