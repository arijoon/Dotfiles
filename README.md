# My dotfiles folder

## Installation (Deprecated)
Install my configuration via
```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/arijoon/Dotfiles/master/install.arijoon.sh)"
```

## Install via home-manager (requires nix installation)
TODO move to a shell script

```sh
ln -s ~/.dotfiles/home-manager ~/.config/home-manager
nix run home-manager/release-23.11 -- switch
```
