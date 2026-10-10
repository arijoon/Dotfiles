{
  config,
  lib,
  pkgs,
  pkgs-latest,
  ...
}:
let
  cfg = config.armanConfig.ai.opencode;

  python = pkgs.python3.withPackages (ps: [ ps.mcp ]);

  searxngMcp = pkgs.writeShellApplication {
    name = "opencode-searxng-mcp";
    text = ''exec ${lib.getExe python} -I ${./searxng-mcp.py} "$@"'';
  };

  opencode = pkgs.writeShellApplication {
    name = "opencode";
    runtimeInputs = [ pkgs.gnugrep ];
    text = ''
      if [ -z "''${LLAMA_SERVER:-}" ]; then
        if grep -qsw vopono.host /etc/hosts; then
          LLAMA_SERVER=vopono.host:${toString cfg.port}
        else
          LLAMA_SERVER=127.0.0.1:${toString cfg.port}
        fi
      fi
      export LLAMA_SERVER
      export SEARXNG_URL="''${SEARXNG_URL:-${cfg.searxngUrl}}"
      export OPENCODE_EXPERIMENTAL_OUTPUT_TOKEN_MAX="''${OPENCODE_EXPERIMENTAL_OUTPUT_TOKEN_MAX:-${toString cfg.output}}"
      exec ${lib.getExe pkgs-latest.opencode} "$@"
    '';
  };
in
{
  options.armanConfig.ai.opencode = {
    enable = lib.mkEnableOption "opencode on a llama.cpp llama-server at $LLAMA_SERVER, with a small prompt that never refuses the operator";

    model = lib.mkOption {
      type = lib.types.str;
      default = "qwen3.8-27b";
      description = "Model id opencode sends. llama-server answers with the one model it loaded, whatever the id.";
    };

    context = lib.mkOption {
      type = lib.types.ints.positive;
      default = 262144;
      description = "llama-server's --ctx-size, so opencode compacts before it runs out.";
    };

    output = lib.mkOption {
      type = lib.types.ints.positive;
      default = 32768;
      description = "Most tokens one reply may take, reasoning included.";
    };

    cost = lib.mkOption {
      type = lib.types.attrsOf lib.types.number;
      default = {
        input = 0.3;
        cache_read = 0.006;
        output = 1.2;
      };
      description = "USD per million tokens opencode shows the local model costing: DeepSeek V4.1 Flash at peak rates, as a yardstick.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5001;
      description = "llama-server's port when $LLAMA_SERVER is unset: on vopono.host inside `with-vpn -H`, else on 127.0.0.1.";
    };

    searxngUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8890";
      description = "SearXNG the search tool asks when $SEARXNG_URL is unset.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      package = opencode;
      settings = {
        autoupdate = false;
        model = "llama/${cfg.model}";
        small_model = "llama/${cfg.model}";
        permission.external_directory = "allow";
        provider.llama = {
          npm = "@ai-sdk/openai-compatible";
          name = "llama.cpp";
          options = {
            baseURL = "http://{env:LLAMA_SERVER}/v1";
            apiKey = "none";
          };
          models.${cfg.model} = {
            tool_call = true;
            reasoning = true;
            interleaved.field = "reasoning_content";
            inherit (cfg) cost;
            limit = {
              inherit (cfg) context output;
            };
          };
        };
        agent = lib.genAttrs [ "build" "plan" "general" ] (_: {
          prompt = builtins.readFile ./prompt.md;
        });
        mcp.searxng = {
          type = "local";
          command = [ (lib.getExe searxngMcp) ];
          environment.SEARXNG_URL = "{env:SEARXNG_URL}";
        };
      };
    };
  };
}
