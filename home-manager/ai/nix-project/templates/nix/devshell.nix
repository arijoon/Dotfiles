{
  lib,
  pkgs,
  config,
  ...
}:
{
  options.devshell = {
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Packages placed on PATH inside the development shell.";
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables exported inside the development shell.";
    };

    shellHook = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shell commands run on entering the development shell.";
    };
  };

  options.env = lib.mkOption {
    type = lib.types.submodule { freeformType = lib.types.attrsOf lib.types.str; };
    default = { };
    description = "Variables the environment loader exports for tasks and apps.";
  };

  config.devshell.packages = [
    pkgs.git
    pkgs.jq
  ];
}
