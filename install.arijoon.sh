sudo apt-get install zsh git vim-gtk3 tmux -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
git clone --recursive https://github.com/arijoon/Dotfiles.git ~/.dotfiles
rm ~/.zshrc
ln -s ~/.dotfiles/vim/ ~/.vim
ln -s ~/.dotfiles/vim/.vimrc ~/.vimrc
ln -s ~/.dotfiles/.zsh/.zshrc ~/.zshrc
ln -s ~/.dotfiles/.tmux.conf ~/.tmux.conf
ln -s ~/.dotfiles/.zsh/agnoster1.zsh-theme ~/.oh-my-zsh/themes/agnoster1.zsh-theme 
ln -s ~/.dotfiles/.zsh/powerlevel9k ~/.oh-my-zsh/custom/themes/powerlevel9k
ln -s ~/.dotfiles/.zsh/powerlevel10k ~/.oh-my-zsh/custom/themes/powerlevel10k

# Install tmux plugin manager
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Install spacevim
curl -sLf https://spacevim.org/install.sh | bash

ln -s ~/.dotfiles/.Spacevim.d ~/.SpaceVim.d
