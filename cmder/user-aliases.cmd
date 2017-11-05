e.=explorer .
ls=ls --show-control-chars -F --color $*
pwd=cd
clear=cls
history=cat %CMDER_ROOT%\config\.history
unalias=alias /d $1
bfg=java -jar C:\Libs\Git\BFG\bfg-1.12.13.jar $*  
gs=git status -s -b $*
gs-gl=git status -s -b | sed -n '$1p' | cut -d" " -f3
ga=git add $*
ga-show=gs | grep -e "^\s.*" -P | cut -d" " -f3 | grep "" -n
ga-show2=gs | grep -e "^\s.*" -P | cut -d" " -f3 | sed -n '2p'
gaa=git add $* .
gd=git diff $*
gdu=git diff $* @ @{upstream} 
gds=for /F "usebackq delims=" %A in (`git status -s -b ^| sed -n '$1p' ^| cut -d" " -f3`) do git diff %A $2 $3 $4 
gm=git commit $*
gma=git commit -am $*
gl1=git log --graph --pretty=format:"%C(dim red)%h%Creset - %C(bold yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit $*
gl=git log --graph --pretty=format:"%C(bold yellow)%d%Creset - %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit $*
gl-f=gl --follow -p -- $*
gls=git log --graph --pretty=format:"%Cred%h%Creset - %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit $*
ggb=git gui blame $*
ggf=gitk --follow --all -p $*
sgrep=grep -rn . -e $* -I --color=always
gshs =git stash show stash^{/$*} -p
gsha =git stash apply stash^{/$*}
gsh=git stash save "$*"
measure-command=powershell -Command Measure-Command { $* }  
nuget2proj=C:\dev\tools\CommandLine\nuget2proj\bin\Release\nuget2proj.exe $*  
gfp=git push --force-with-lease  
tibbin=cd C:\dev\TIBCO\TIBRV\bin  
mp-stat=cat log.log
cgrep=grep --color auto
