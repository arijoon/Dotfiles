Config { font = "xft:Ubuntu Mono:pixelsize=14:antialias=true:hinting=true"
        , borderColor = "black"
        , border = TopB
        , bgColor = "black"
        , fgColor = "grey"
        , position = TopW L 100
        , commands = [ Run Cpu ["-L","3","-H","50","--normal","green","--high","red"] 10
                        , Run Memory ["-t","Mem: <usedratio>%"] 10
                        , Run Com "uname" ["-s","-r"] "" 36000
                        , Run Date "%a %b %_d %Y %H:%M:%S" "date" 10
                        ]
        , sepChar = "%"
        , alignSep = "}{"
        , template = "%cpu% | %memory% | }{<fc=#ee9a00>%date%</fc> | %uname% "
        }
