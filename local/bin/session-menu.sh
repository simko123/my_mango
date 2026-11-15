#!/usr/bin/env bash
set -euo pipefail

# Toggle: pressing the shortcut again closes only this menu.
for pid in $(pgrep -x fuzzel || true); do
  if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q -- '--namespace session'; then
    kill "$pid" 2>/dev/null || true
    exit 0
  fi
done

options=("Lock" "Logout" "Suspend" "Reboot" "Shutdown")

choice=$(printf '%s\n' "${options[@]}" | fuzzel \
  --dmenu \
  --namespace session \
  --prompt "Session  " \
  --lines 5 \
  --width 22 \
  --background-color 1c181fe6 \
  --text-color e9e2f0ff \
  --selection-color d5bee94d \
  --selection-text-color ffffffff \
  --border-color d5bee93d \
  --border-width 1 \
  --border-radius 14 \
  --font "JetBrainsMono Nerd Font:size=11") || exit 0

case "$choice" in
  Lock)
    exec "$HOME/.local/bin/lock-screen.sh"
    ;;
  Logout)
    if [[ -n "${XDG_SESSION_ID:-}" ]]; then
      exec loginctl terminate-session "$XDG_SESSION_ID"
    else
      exec mmsg dispatch quit
    fi
    ;;
  Suspend)
    exec systemctl suspend
    ;;
  Reboot)
    exec systemctl reboot
    ;;
  Shutdown)
    exec systemctl poweroff
    ;;
  *)
    exit 0
    ;;
esac
