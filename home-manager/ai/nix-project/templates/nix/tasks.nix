{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.tasks;

  taskType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Summary shown by 'task --list'.";
      };

      command = lib.mkOption {
        type = lib.types.lines;
        description = "Bash run from the repository root. Arguments arrive as \"$@\".";
      };

      runtimeInputs = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = ''
          Everything the command needs on PATH. A task must carry its own tools:
          it runs outside the devshell as often as in it.
        '';
      };

      secrets = {
        required = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Keys the env loader decrypts for the task from the env's and the
            shared sops files, when the caller hasn't set them. One that neither
            file holds stops the task.
          '';
        };

        optional = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Keys the env loader decrypts for the task as required ones are, exporting each only when a file holds it.";
        };

        own = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Required or optional keys the env loader takes from the env's own sops file alone, never the shared one.";
        };

        debug = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Required or optional keys the env loader takes from the env's debug sops file alone; a task declaring only these decrypts that file with the debug key, never touching the env's own.";
        };
      };

      fresh = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether 'task' always runs it through nix run on the current tree rather
          than the store path evaluated when the devshell was entered: for a task
          whose script embeds a build output or a file generated from the env.
        '';
      };
    };
  };

  toPackage =
    name: task:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.git ] ++ task.runtimeInputs;
      text = ''
        cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
        ${task.command}
      '';
    };

  taskPackages = lib.mapAttrs toPackage cfg;

  width = lib.foldl' (acc: name: lib.max acc (lib.stringLength name)) 0 (lib.attrNames cfg);
  pad = name: name + lib.fixedWidthString (width - lib.stringLength name + 2) " " "";

  index = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: task: "  ${pad name}${task.description}") cfg
  );

  exePath = package: lib.escapeShellArg (builtins.unsafeDiscardStringContext (lib.getExe package));

  branches = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: package: "  ${name}) exe=${lib.optionalString (!cfg.${name}.fresh) (exePath package)} ;;"
    ) config.appPackages.tasks
  );

  envBranches = lib.concatMapStrings (env: "  ${env}) env=${env}; shift ;;\n") (
    lib.remove config.taskEnv config.taskEnvs
  );

  declaredIn =
    env:
    (if env == config.envName then config else config.evalEnv env config.envModules.${env})
    .actionSecrets.tasks or { };

  loaders = lib.concatMapStrings (env: ''
      ${env})
        case "$name" in
    ${lib.concatStrings (
      lib.mapAttrsToList (name: declared: ''
            ${name})
        ${config.envLoader env declared}
              ;;
      '') (declaredIn env)
    )}
          *)
    ${config.envLoader env null}
            ;;
        esac
        ;;
  '') config.taskEnvs;

  declared = lib.filterAttrs (_name: task: task.secrets.required ++ task.secrets.optional != [ ]) cfg;

  runner = pkgs.writeShellApplication {
    name = "task";
    runtimeInputs = config.envLoaderInputs;
    text = ''
      usage() {
        cat <<'INDEX'
      Usage: task [<env>] <name> [args...]

      Environments: ${lib.concatStringsSep ", " config.taskEnvs}; ${config.taskEnv} when none is given.

      ${index}
      INDEX
      }

      env=${config.taskEnv}
      case "''${1:-}" in
      ${envBranches}
      esac

      case "''${1:-}" in
        "" | -l | --list | -h | --help) usage; exit 0 ;;
      ${branches}
        *) echo "task: no such task '$1'" >&2; usage >&2; exit 1 ;;
      esac

      name="$1"
      shift

      case "$env" in
      ${loaders}
      esac

      if [ -x "$exe" ]; then
        exec "$exe" "$@"
      fi

      exec nix run "$root#p.$env.tasks.$name" -- "$@"
    '';
  };

in
{
  options = {
    tasks = lib.mkOption {
      type = lib.types.attrsOf taskType;
      default = { };
      description = "Project tasks, dispatched by the 'task' command.";
    };

    taskPackages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      description = "Built task commands, so one task can compose another by store path.";
    };

    taskEnv = lib.mkOption {
      type = lib.types.str;
      default = "dev";
      description = ''
        Environment the devshell's 'task' wrapper dispatches into. It selects an
        attribute path to run; it is not readable as "which environment am I".
      '';
    };

    taskEnvs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ config.taskEnv ];
      description = ''
        Environments the 'task' wrapper can dispatch into: 'task stg run' runs
        'run' under stg, as 'nix run .#p.stg.tasks.run' does.
      '';
    };

    envName = lib.mkOption {
      type = lib.types.str;
      default = config.taskEnv;
      description = ''
        Name of the env this evaluation is for, as 'task <env>' takes it. For
        messages only: behaviour comes from env keys, never from this.
      '';
    };

    envFile = lib.mkOption {
      type = lib.types.str;
      default = "nix/envs/${config.envName}/default.nix";
      description = "The env's module, relative to the repository root, for messages naming where to set a key.";
    };

    envModules = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Every env's module, by name, as the flake evaluates them.";
    };

    evalEnv = lib.mkOption {
      type = lib.types.raw;
      default = _name: _module: throw "evalEnv is set by the flake";
      description = "Evaluates the project for an env: takes the env's name and module, returns its config.";
    };

    taskRunner = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = runner;
      description = "The 'task' command on the devshell's PATH, built as .#task.";
    };
  };

  config = {
    inherit taskPackages;

    tasks.run-any = {
      description = "Run any command with the environment loaded";
      runtimeInputs = [
        pkgs.bash
        pkgs.coreutils
      ];
      command = ''
        if [ "$#" -eq 0 ]; then
          echo "run-any: needs a command, e.g. task run-any psql -c 'select 1'" >&2
          exit 1
        fi

        exec "$@"
      '';
    };

    actionSecrets.tasks = lib.mapAttrs (name: task: {
      inherit name;
      inherit (task.secrets)
        required
        optional
        own
        debug
        ;
    }) declared;

    apps.tasks = {
      description = "Developer tasks, also on the devshell PATH as 'task'";
      actions = taskPackages;
    };

    devshell.packages = [ runner ];
  };
}
