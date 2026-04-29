{ pkgs, pkgs-latest, ... }:
let
  inherit (builtins) concatStringsSep;

  sandbox-run = pkgs.writeShellApplication {
    name = "sandbox-run";
    runtimeInputs = [ pkgs-latest.landrun ];
    text = builtins.readFile ./scripts/sandbox-run;
  };

  # Build a sandbox-run preset. Path lists and env-var names are baked in
  # at nix-eval time and exported via the SANDBOX_*_PATHS / SANDBOX_FORWARD_ENV
  # contract that sandbox-run reads. $HOME (and any other env refs) inside
  # paths are expanded by bash at run time.
  mkSandboxPreset =
    {
      name,
      rw ? [ ],
      rox ? [ ],
      ro ? [ ],
      envs ? [ ],
      noNetwork ? false,
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ sandbox-run ];
      text = ''
        export SANDBOX_RW_PATHS=${"\""}${concatStringsSep "\n" rw}${"\""}
        export SANDBOX_ROX_PATHS=${"\""}${concatStringsSep "\n" rox}${"\""}
        export SANDBOX_RO_PATHS=${"\""}${concatStringsSep "\n" ro}${"\""}
        export SANDBOX_FORWARD_ENV=${"\""}${concatStringsSep "\n" envs}${"\""}
        exec sandbox-run ${if noNetwork then "--no-network " else ""}"$@"
      '';
    };

  sandbox-ai = mkSandboxPreset {
    name = "sandbox-ai";
    rw = [
      # Claude Code
      "$HOME/.claude"
      "$HOME/.claude.json"
      "$HOME/.cache/claude-cli-nodejs"
      # Gemini CLI
      "$HOME/.gemini"
      "$HOME/.config/gemini"
      # OpenAI Codex / generic
      "$HOME/.codex"
      "$HOME/.config/openai"
    ];
    ro = [
      "$HOME/.config/git"
    ];
    envs = [
      "ANTHROPIC_API_KEY"
      "ANTHROPIC_AUTH_TOKEN"
      "GEMINI_API_KEY"
      "GOOGLE_API_KEY"
      "OPENAI_API_KEY"
    ];
  };
in
{
  home.packages = [
    sandbox-run
    sandbox-ai
  ];
}
