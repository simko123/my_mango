#!/usr/bin/env bash

set -euo pipefail

mapfile -t profiles < <(
  powerprofilesctl list |
    sed -nE 's/^[[:space:]]*\*?[[:space:]]*(performance|balanced|power-saver):.*/\1/p'
)

if [[ ${#profiles[@]} -eq 0 ]]; then
  command -v notify-send >/dev/null && \
    notify-send -a "Power profile" "power-profiles-daemon is not available"
  exit 1
fi

if command -v fuzzel >/dev/null 2>&1; then
  choice=$(printf '%s\n' "${profiles[@]}" | fuzzel \
    --dmenu \
    --prompt "Power profile  " \
    --lines 3 \
    --width 22 \
    --background-color 1c181fe6 \
    --text-color e9e2f0ff \
    --selection-color d5bee94d \
    --selection-text-color ffffffff \
    --border-color d5bee93d \
    --border-width 1 \
    --border-radius 14 \
    --font "JetBrainsMono Nerd Font:size=11") || exit 0
elif command -v rofi >/dev/null 2>&1; then
  choice=$(printf '%s\n' "${profiles[@]}" | rofi -dmenu -p "Power profile") || exit 0
else
  command -v notify-send >/dev/null && \
    notify-send -a "Power profile" "Install fuzzel or rofi to choose a power profile"
  exit 1
fi

[[ -z "${choice}" ]] && exit 0

powerprofilesctl set "${choice}"

if command -v notify-send >/dev/null 2>&1; then
  notify-send -a "Power profile" "Power profile set to ${choice}"
fi
