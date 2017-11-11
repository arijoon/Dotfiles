sudo apt-get install zsh git -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
git clone --recursive https://github.com/arijoon/Dotfiles.git ~/.dotfiles
rm ~/.zshrc
ln -s ~/.dotfiles/.vim/ ~/.vim
ln -s ~/.dotfiles/.vim/.vimrc ~/.vimrc
ln -s ~/.dotfiles/.zsh/.zshrc ~/.zshrc
ln -s ~/.dotfiles/.zsh/agnoster1.zsh-theme ~/.oh-my-zsh/themes/agnoster1.zsh-theme 
ln -s ~/.dotfiles/.zsh/powerlevel9k ~/.oh-my-zsh/custom/themes/powerlevel9k
