{
  lib,
  config,
  ...
}:
let
  cfg = config.checks;

  run = name: ''
    echo "check: ${name}"
    ${lib.getExe config.taskPackages.${name}}
  '';
in
{
  options.checks.steps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Task names `task check` runs, in order. The module that owns a gate
      registers it here, so the gate grows with the components rather than
      being edited in one place.
    '';
  };

  config.tasks.check = {
    description = "Every registered gate, in order: what must pass before merging";
    fresh = lib.any (name: config.tasks.${name}.fresh) cfg.steps;
    command =
      if cfg.steps == [ ] then
        ''echo "check: no steps registered yet"''
      else
        lib.concatMapStrings run cfg.steps;
  };
}
