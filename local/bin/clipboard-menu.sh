#!/usr/bin/env bash
set -euo pipefail

# Toggle: pressing SUPER+V again closes only the clipboard menu.
for pid in $(pgrep -x fuzzel || true); do
    if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q -- '--namespace clipboard'; then
        kill "$pid" 2>/dev/null || true
        exit 0
    fi
done

selection=$(cliphist list | fuzzel --dmenu --namespace clipboard --prompt "Clipboard: ") || exit 0
[ -n "$selection" ] || exit 0

printf '%s' "$selection" | cliphist decode | wl-copy
