if [[ -n "${INSTALL_NIX}" ]]; then
sh <(curl -L https://nixos.org/nix/install) --no-daemon
fi

nix-shell -p git --run 'git clone --recursive https://github.com/arijoon/Dotfiles.git ~/.dotfiles'

ln -s ~/.dotfiles/home-manager ~/.config/home-manager
cp ~/.dotfiles/home-manager/local.nix.template ~/.dotfiles/home-manager/local.nix

cd ~/.dotfiles/home-manager
nix run .#home-manager -- switch
