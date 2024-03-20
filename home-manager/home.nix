{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "arman";
  home.homeDirectory = "/home/arman";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
    bat
    fd
    fzf
    httpie
    ncdu
    niv
    nix-du
    nixd
    nixpkgs-fmt
    ripgrep
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;
    ".tmux.conf".source = home-files/.tmux.conf;
    ".tmux/plugins/tpm".source = pkgs.fetchFromGitHub {
      owner = "tmux-plugins";
      repo = "tpm";
      rev = "99469c4a9b1ccf77fade25842dc7bafbc8ce9946";
      sha256 = "sha256-hW8mfwB8F9ZkTQ72WQp/1fy8KL1IIYMZBtZYIwZdMQc=";
    };
    # Only link starter config
    ".config/nvim/" = {
      source = ./neovim;
      recursive = true;
    };

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. If you don't want to manage your shell through Home
  # Manager then you have to manually source 'hm-session-vars.sh' located at
  # either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/arman/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    EDITOR = "nvim";
    KEYTIMEOUT = 1;
    TERM = "alacritty";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
  programs.git = {
    enable = true;
    aliases = {
      tags = "tag --sort=-creatordate";
      aliases = "config --get-regexp alias";
      co = "checkout";
      coi = "!git branch | grep \"$1\" -m 1 | xargs git checkout";
      br = "branch";
      ci = "commit";
      gl = "log --graph --pretty=format:\"%C(dim red)%h%Creset - %C(bold yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset\" --abbrev-commit";
      gls = "log --pretty=oneline --abbrev-commit";
      gfp = "push --force-with-lease";
      fe = "!git fetch origin $1:$1";
      fem = "fetch origin master:master";
      gs = "status -s -b";
    };
    ignores = [
      ".direnv"
      ".vscode"
      ".venv"
      "*.private.*"
      "ay.local.*"
    ];

    # Populate signing section
    # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.git.signing.gpgPath
    # signing
    userEmail = "arman@yaraee.net";
    userName = "arijoon";

    extraConfig = {
      core = {
        fscache = true;
        # Win machines are case insensitive
        # having the same filename with two different
        # names can cause issues
        ignorecase = true;
        eol = "lf";
      };
    };
  };

  # Shell
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    history.extended = true;

    localVariables = {
      COMPLETION_WAITING_DOTS = "true";
      DISABLE_UNTRACKED_FILES_DIRTY = "true";
      # FZF command setup
      # export FZF_CTRL_T_COMMAND="fd --type f --hidden";
      FZF_CTRL_T_OPTS = "--preview 'bat --color=always --line-range :50 {}'";
      FZF_ALT_C_OPTS = "--preview 'tree -c {} | head -50'";
    };

    initExtra = ''
      source ${./zsh/p10k.zsh}
      bindkey -v
      bindkey -M vicmd v edit-command-line
      bindkey '^R' history-beginning-search-backward
      bindkey '^W' history-beginning-search-forward
      bindkey "^[[H" beginning-of-line
      bindkey "^[[F" end-of-line

      # Access systemwide zsh completions
      fpath+=(/usr/share/zsh/vendor-completions)

      # For some reason home-manager does not
      # load its own env
      . ~/.nix-profile/etc/profile.d/nix.sh

      # Load FZF setup
      fzf-share &> /dev/null && {
        source $(fzf-share)/completion.zsh
        source $(fzf-share)/key-bindings.zsh
        source ${./zsh/fzf-completions.zsh}
      }

      # Manually load as it seems to not trigger
      # due to oh-my-zsh
      autoload -U compinit && compinit
    '';

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "github"
        "gitignore"
        "kubectl"
        "docker"
        "fzf"
        # "nix-zsh-completions"
      ];
      # This might not be required as we can manage the theme
      # without on-my-zsh
      # theme = "powerlevel10k/powerlevel10k";
    };

    shellAliases = {
      gco = "git checkout $(git branch | fzf)";
      gcor = "git checkout $(git branch --remote | fzf)";
    };

    syntaxHighlighting = {
      enable = true;
      highlighters = [
        "brackets"
      ];
      # TODO unable with next release, not yet on 23.11
      # patterns = {
      #   "rm -rf *" = "fg=white,bold,bg=red";
      # };
    };

    zsh-abbr = {
      enable = true;
      abbreviations = {
        k = "kubectl";
      };
    };
  };

  # Vim
  # For now using neovim's built in plugin manger
  # but can switch to managing all via nix
  # Example: https://github.com/azuwis/nix-config/blob/9addb1ba8aad35e50695185e3bdcc747a146f31d/common/nvchad/home.nix
  programs.neovim = {
    enable = true;
    # defaultEditor = true;
    viAlias = true;
    vimdiffAlias = true;
    extraConfig = ":luafile ~/.config/nvim/init.lua";
  };
}
