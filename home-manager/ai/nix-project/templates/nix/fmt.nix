{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.formatting;
in
{
  options.formatting.formatters = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = ''
      Tools the formatters in treefmt.toml call. The fmt and fmt-check tasks
      carry them on PATH; a module that adds a formatter appends its tool here.
    '';
  };

  config = {
    formatting.formatters = [
      pkgs.nixfmt
      pkgs.prettier
    ];

    devshell.packages = [ pkgs.treefmt ] ++ cfg.formatters;

    tasks.fmt = {
      description = "Format every file treefmt knows about";
      runtimeInputs = cfg.formatters;
      command = ''exec ${lib.getExe pkgs.treefmt} "$@"'';
    };

    tasks.fmt-check = {
      description = "Fail if anything is unformatted";
      runtimeInputs = cfg.formatters;
      command = ''exec ${lib.getExe pkgs.treefmt} --fail-on-change "$@"'';
    };

    checks.steps = [ "fmt-check" ];
  };
}
