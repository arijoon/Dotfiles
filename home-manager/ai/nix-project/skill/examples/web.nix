{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.web;
  nodejs = config.languages.nodejs;

  inputs = [
    nodejs.package
    nodejs.pnpm
  ];
in
{
  options.services.web.sourceDir = lib.mkOption {
    type = lib.types.str;
    default = "web";
    description = "Frontend sources, relative to the repository root.";
  };

  options.env = {
    API_URL = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8080";
      description = "Backend the frontend dev server proxies /api to.";
    };

    WEB_PORT = lib.mkOption {
      type = lib.types.str;
      default = "5173";
      description = "Port the frontend dev server listens on.";
    };
  };

  config = {
    apps.web = {
      description = "The frontend, built to static files";

      actions.build = pkgs.writeShellApplication {
        name = "web-build";
        runtimeInputs = inputs ++ [ pkgs.git ];
        text = ''
          cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")/${cfg.sourceDir}"

          pnpm install --frozen-lockfile
          exec pnpm build
        '';
      };
    };

    tasks = {
      web = {
        description = "Run the frontend dev server on WEB_PORT, proxying /api to API_URL";
        runtimeInputs = inputs;
        command = ''
          cd ${cfg.sourceDir}
          exec pnpm dev "$@"
        '';
      };

      pnpm = {
        description = "Run pnpm in the frontend with the environment loaded";
        runtimeInputs = inputs;
        command = ''
          cd ${cfg.sourceDir}
          exec pnpm "$@"
        '';
      };

      web-check = {
        description = "Install, type-check and test the frontend";
        runtimeInputs = inputs;
        command = ''
          cd ${cfg.sourceDir}
          pnpm install --frozen-lockfile
          pnpm check
          pnpm test
        '';
      };
    };

    services.run.processes.web = "web";

    checks.steps = lib.mkOrder 1600 [ "web-check" ];
  };
}
