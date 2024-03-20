sh <(curl -L https://nixos.org/nix/install) --no-daemon

nix-shell -p git -c 'git clone --recursive https://github.com/arijoon/Dotfiles.git ~/.dotfiles'

ln -s ~/.dotfiles/home-manager ~/.config/home-manager
cp ~/.dotfiles/home-manager/local.nix.template ~/.dotfiles/home-manager/local.nix
nix run home-manager/release-23.11 -- switch
