Config { font = "xft:Ubuntu Mono:pixelsize=14:antialias=true:hinting=true"
        , borderColor = "black"
        , border = TopB
        , bgColor = "black"
        , fgColor = "grey"
        , allDesktops = True
        , position = TopW L 150
        , commands = [ Run UnsafeXPropertyLog "_XMONAD_LOG_0"
                        , Run Cpu ["-t", "<fn=1></fn>Cpu: <total>%", "-H","70", "--high", "red"] 20
                        , Run Memory ["-t","Mem: <usedratio>% <used>/<total> Gb", "-d", "1", "--","--scale", "1024"] 10
                        , Run BatteryP ["BAT0"]
                            [
                                "-t", "<acstatus><watts> (<left>%)",
                                "-L", "10", "-H", "80", "-p", "3",
                                "--", "-O", "<fc=green>On</fc> - ", "-i", "",
                                "-L", "-15", "-H", "-5",
                                "-l", "red", "-m", "blue", "-h", "green"
                            ] 600
                        , Run Com "osname" [] "" 36000
                        , Run Com "gputemp" [] "" 600
                        , Run Com "cputemp" [] "" 20
                        , Run Com "diskusage" [] "" 20
                        , Run Date "%a %b %_d %Y %H:%M:%S" "date" 10
                        , Run Network "wlo1" ["-t", "<fn=0>U :</fn> <rx>kb <fn=0>D :</fn> <tx>kb"] 20
                        -- Not functioning
                        -- , Run DiskU [("/", "<used>/<size>")] [] 60
                        -- , Run DiskIO [("/", "<read>/<write>")] [] 20
                        , Run XMonadLog
                        ]
        , sepChar = "%"
        , alignSep = "}{"
       , template = "\
            \%XMonadLog%\
            \    \
            \}\
            \<fc=#ee9a00>%date%</fc> | %osname%\
            \{\
            \%wlo1%\
            \     \
            \|\
            \     \
            \%diskusage%\
            \     \
            \|\
            \     \
            \%memory%\
            \     \
            \|\
            \     \
            \%cpu% %cputemp%\
            \     \
            \|\
            \     \
            \%gputemp%\
            \     \
            \|\
            \   \
            \%battery%"
        }
