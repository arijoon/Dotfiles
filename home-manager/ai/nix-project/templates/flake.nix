{
  description = "@PROJECT@ development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        lib = nixpkgs.lib;

        evalProject =
          overrides:
          (lib.evalModules {
            specialArgs = { inherit pkgs lib; };
            modules = [ ./nix ] ++ overrides;
          }).config;

        evalEnv =
          name: module:
          evalProject [
            module
            {
              envName = name;
              taskEnv = defaultEnv;
              taskEnvs = lib.attrNames envModules;
              inherit envModules evalEnv;
            }
          ];

        shellConfig = environments.${defaultEnv};

        mkDevShell =
          cfg:
          pkgs.mkShell (
            {
              packages = cfg.packages;

              shellHook = ''
                PRJ_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
                export PRJ_ROOT
              ''
              + cfg.shellHook;
            }
            // cfg.env
          );

        envModules = lib.mapAttrs (name: _: ./nix/envs + "/${name}") (
          lib.filterAttrs (name: type: type == "directory" && name != "shared") (builtins.readDir ./nix/envs)
        );

        defaultEnv = "dev";

        environments = lib.mapAttrs evalEnv envModules;

        toApp = package: {
          type = "app";
          program = lib.getExe package;
        };

        runnersOf =
          envName: cfg:
          let
            runner =
              appName: actionName: package:
              pkgs.writeShellApplication {
                name = "${appName}-${actionName}";
                runtimeInputs = cfg.envLoaderInputs;
                text = ''
                  ${cfg.envLoader envName (cfg.actionSecrets.${appName}.${actionName} or null)}
                  exec ${lib.getExe package} "$@"
                '';
              };
          in
          lib.mapAttrs (appName: lib.mapAttrs (runner appName)) cfg.appPackages;

        runners = lib.mapAttrs runnersOf environments;
      in
      {
        devShells.default = mkDevShell shellConfig.devshell;

        apps.p = lib.mapAttrs (_env: lib.mapAttrs (_app: lib.mapAttrs (_action: toApp))) runners;

        legacyPackages.p = lib.mapAttrs (
          envName: actions: actions // { inherit (environments.${envName}) env; }
        ) runners;

        packages =
          lib.concatMapAttrs (
            name: app: lib.optionalAttrs (app.package != null) { ${name} = app.package; }
          ) environments.${defaultEnv}.apps
          // {
            task = shellConfig.taskRunner;
          };
      }
    );
}
