#!/bin/sh
# Prints ONE line ("<percent>|<top apps>") each time RAM usage crosses 75%.
# It stays silent otherwise, and re-arms once usage falls back under 70%.
# The app list is only built at the moment of crossing, never on every check.

LIMIT=75
REARM=70        # must ALWAYS be lower than LIMIT, or the alert logic breaks
EVERY=10        # seconds between checks (one tiny /proc/meminfo read)
hot=0

while true; do
    used=$(awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{printf "%d", (t-a)*100/t}' /proc/meminfo)

    if [ "$used" -ge "$LIMIT" ]; then
        if [ "$hot" -eq 0 ]; then
            hot=1
            # Sum memory per program name (so Chrome's 30 processes count as one),
            # then take the 3 biggest.
            top=$(ps -eo rss=,comm= | awk '
                { r=$1; $1=""; sub(/^ /,""); m[$0]+=r }
                END { for (k in m) printf "%d\t%s\n", m[k], k }' \
                | sort -rn | head -3 \
                | awk -F'\t' '{ printf "%s%s  %.1f GB", (NR>1 ? "\n" : ""), $2, $1/1048576 }')
            echo "$used|$top"
        fi
    elif [ "$used" -lt "$REARM" ]; then
        hot=0
    fi

    sleep "$EVERY"
done
