#!/bin/sh
case "$1" in
  greet)
    h=$(date +%-H)
    if   [ "$h" -lt 5 ];  then echo "still up, $USER?"
    elif [ "$h" -lt 12 ]; then echo "good morning, $USER"
    elif [ "$h" -lt 18 ]; then echo "good afternoon, $USER"
    else echo "good evening, $USER"; fi
    ;;
  day)
    p=$(( ($(date +%-H) * 60 + $(date +%-M)) * 100 / 1440 ))
    n=$(( p / 10 )); bar=""; i=0
    while [ "$i" -lt 10 ]; do
      if [ "$i" -lt "$n" ]; then bar="${bar}▰"; else bar="${bar}▱"; fi
      i=$(( i + 1 ))
    done
    echo "${bar}  ${p}% of today gone"
    ;;
  bat)
    c=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
    [ -n "$c" ] && echo "󰁹 ${c}%"
    ;;
esac
