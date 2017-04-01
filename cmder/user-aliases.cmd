e.=explorer .
ls=ls --show-control-chars -F --color $*
pwd=cd
clear=cls
history=cat %CMDER_ROOT%\config\.history
unalias=alias /d $1
bfg=java -jar C:\Libs\Git\BFG\bfg-1.12.13.jar $*  
gs=git status -s -b $*
ga=git add $*
gaa=git add $* .
gd=git diff $*
gdu=git diff $* @ @{upstream} 
gm=git commit $*
gma=git commit -am $*
gl=git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit $*
gl-f=gl --follow -p -- $*
gls=git log --graph --pretty=format:"%Cred%h%Creset - %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit $*
ggb=git gui blame $*
ggf=gitk --follow --all -p $*