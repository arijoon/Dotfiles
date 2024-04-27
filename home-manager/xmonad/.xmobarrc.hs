Config { font = "xft:Ubuntu Mono:pixelsize=14:antialias=true:hinting=true"
        , borderColor = "black"
        , border = TopB
        , bgColor = "black"
        , fgColor = "grey"
        , allDesktops = True
        , position = TopW L 100
        , commands = [ Run UnsafeXPropertyLog "_XMONAD_LOG_0"
                        ,Run Cpu ["-L","3","-H","50","--normal","green","--high","red"] 10
                        , Run Memory ["-t","Mem: <usedratio>%"] 10
                        , Run Com "uname" ["-s","-r"] "" 36000
                        , Run Date "%a %b %_d %Y %H:%M:%S" "date" 10
                        , Run Com "cpuTemp.sh" [] "cpu" 10
                        , Run Com "gpuTemp.sh" [] "gpu" 10
                        , Run Com "wifi.sh" [] "network" 10
                        ]
        , sepChar = "%"
        , alignSep = "}{"
       , template = "\
            \    \
            \%_XMONAD_LOG_0%\
            \}\
            \<fc=#ee9a00>%date%</fc> | %uname%\
            \{\
            \     \
            \%memory%\
            \     \
            \|\
            \     \
            \%cpu%\
            \     \
            \|\
            \     \
            \%gpu%\
            \     \
            \|\
            \   \
            \%trayerpad%"
        -- , template = "%cpu% | %memory% | }{<fc=#ee9a00>%date%</fc> | %uname% "
        }
