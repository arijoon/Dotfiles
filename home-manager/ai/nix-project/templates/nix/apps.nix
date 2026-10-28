{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.apps;

  loader = envName: declared: ''
    root="''${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
    ${config.secrets.loadFragment config.secrets.keys.${envName} declared}
    __env_entries="$(nix eval --json "$root#p.${envName}.env" | jq -r 'to_entries[] | select(.value != null) | "\(.key) \(.value | @base64)"')"

    while read -r __env_key __env_value; do
      [ -n "$__env_key" ] || continue
      if [ -z "''${!__env_key+set}" ]; then
        export "$__env_key=$(printf %s "$__env_value" | base64 -d)"
      fi
    done <<< "$__env_entries"

    unset __env_entries __env_key __env_value
  '';

  appType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Summary of what the component is.";
      };

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = ''
          Built artefact, exposed as 'packages.<name>'. When it has a main
          program, it also defines a 'run' action that executes it.
        '';
      };

      actions = lib.mkOption {
        type = lib.types.attrsOf lib.types.package;
        default = { };
        description = "Further runnables, reached as 'nix run .#p.<env>.<name>.<action>'.";
      };
    };
  };

  actionsOf =
    app:
    (lib.optionalAttrs (app.package != null && app.package.meta ? mainProgram) { run = app.package; })
    // app.actions;
in
{
  options = {
    apps = lib.mkOption {
      type = lib.types.attrsOf appType;
      default = { };
      description = ''
        Deployable components. Each one is reached as
        'nix run .#p.<env>.<name>.<action>', which resolves the environment at
        run time rather than baking it into the derivation.
      '';
    };

    appPackages = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.package);
      readOnly = true;
      description = "Per-component actions, carrying no environment of their own.";
    };

    envLoader = lib.mkOption {
      type = lib.types.functionTo (lib.types.functionTo lib.types.lines);
      readOnly = true;
      description = ''
        Shell fragment that decrypts the secrets a task declares and reads an
        environment's variables out of the flake at run time, and exports the
        ones the caller has not already set, skipping null ones. Takes the
        environment's name and the task's declaration, or null. Leaves the
        repository root in 'root'.
      '';
    };

    actionSecrets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.raw);
      default = { };
      description = "The secrets each component's actions declare, by component and action: name, required and optional keys.";
    };

    envLoaderInputs = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      readOnly = true;
      description = "Runtime inputs a script needs before it can use 'envLoader'.";
    };
  };

  config = {
    appPackages = lib.mapAttrs (_name: actionsOf) cfg;

    envLoader = loader;

    envLoaderInputs = [
      pkgs.git
      pkgs.jq
      pkgs.coreutils
    ];
  };
}
