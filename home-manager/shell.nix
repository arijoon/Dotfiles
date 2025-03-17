{ config, pkgs, ... }:
{
  programs.nushell = {
    enable = true;

    shellAliases = {
      gco = "git checkout (git branch | fzf)";
      gcor = "git checkout (git branch --remote | fzf)";
      gpsup = "git push --set-upstream origin (git_current_branch)";
    };

    extraConfig = ''
        $env.config.buffer_editor = "vi";
        $env.config.edit_mode = "vi";
        $env.config.show_banner = false;
    '';
  };

  programs.carapace = {
    enable = true;
    enableNushellIntegration = true;
  };

  programs.starship = {
    enable = true;
    enableNushellIntegration = true;

    settings = {
      add_newline = true;
      right_format = "$nix_shell$direnv$cmd_duration$time";
      format = ''
        $directory$git_branch$git_status$fill
        $character
      '';
      fill = {
        disabled = false;
        symbol = ".";
      };

      direnv = {
        disabled = false;
        format = "[$symbol$loaded$allowed]($style)";
        allowed_msg = "";
        loaded_msg = "";
      };

      nix_shell = {
        disabled = false;
        symbol = "nix-shell ";
        format = "[$symbol]($style)";
      };

      time = {
        disabled = false;
        format ="[$time]($style)";
        time_format = "%T";
      };

      directory = {
        format = "[$path]($style) ";
        truncation_length = 3;
        style = "blue";
      };

      git_branch = {
        symbol = ""; # Remove Nerd Font branch symbol
        format = "[$branch]($style) ";
      };

      git_status = {
        format = "[($all_status$ahead_behind)]($style) ";
      };

      cmd_duration = {
        disabled = false;
        format = "[$duration]($style) ";
      };

      character = {
        # Nushell automatically adds a symbol for Vi modes
        format = ""; 
        success_symbol = "[>](bold green)";
        error_symbol = "[>](bold red)";
      };
    };
  };

}
