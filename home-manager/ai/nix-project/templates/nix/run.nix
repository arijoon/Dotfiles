{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.run;

  processes = pkgs.writeText "process-compose.yaml" (
    builtins.toJSON {
      version = "0.5";
      processes = lib.mapAttrs (_name: task: {
        command = lib.getExe config.taskPackages.${task};
        availability.restart = "on_failure";
      }) cfg.processes;
    }
  );
in
{
  options.services.run = {
    processes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        What `task run` supervises, as process name to task name. Each runs the
        store path its task does, so there is one definition of how a
        component starts.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8100;
      description = "Port process-compose's HTTP API listens on, which is how a second terminal attaches.";
    };
  };

  config.tasks.run = lib.mkIf (cfg.processes != { }) {
    description = "Run every process in services.run.processes together under process-compose";
    runtimeInputs = [ pkgs.process-compose ];
    command = ''
      exec process-compose --config ${processes} --port ${toString cfg.port} "$@"
    '';
  };
}
