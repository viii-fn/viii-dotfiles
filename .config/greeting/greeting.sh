#!/usr/bin/env bash
dir="$HOME/.config/greeting"
mapfile -t art < "$dir/lambda.txt"

line=$(shuf -n1 "$dir/quotes.txt")
quote="${line%%|*}"
author="${line##*|}"

mapfile -t q < <(printf '"%s"' "$quote" | fold -s -w 44)
q+=("  — $author")

n=${#art[@]}
off=$(( (n - ${#q[@]}) / 2 )); (( off < 0 )) && off=0

echo
for ((i=0; i<n; i++)); do
  j=$((i-off)); text=""
  (( j >= 0 && j < ${#q[@]} )) && text="${q[j]}"
  printf '  \e[38;5;217m%s\e[0m    \e[3m%s\e[0m\n' "${art[i]}" "$text"
done
echo
