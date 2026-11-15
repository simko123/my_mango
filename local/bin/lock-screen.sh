#!/usr/bin/env bash
# Lock the current Wayland session.
# Uses swaylock by default and can use hyprlock when explicitly requested.

set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
hypr_config="$config_home/hypr/hyprlock.conf"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
log_file="$runtime_dir/lock-screen.log"
backend="${LOCK_SCREEN_BACKEND:-swaylock}"

mode="foreground"
case "${1:-}" in
  "") ;;
  -b | --background) mode="background" ;;
  --swaylock) backend="swaylock" ;;
  --hyprlock) backend="hyprlock" ;;
  -h | --help)
    cat <<'EOF'
Usage: lock-screen.sh [--background] [--swaylock|--hyprlock]

Locks the current Wayland session. Uses swaylock by default, with the current
wallpaper blurred and darkened automatically.

  -b, --background   Detach the locker and return immediately. Useful for
                     swayidle before-sleep and suspend hooks.
  --swaylock         Force swaylock (default).
  --hyprlock         Use hyprlock when it is installed and configured.
                     Can also be enabled with LOCK_SCREEN_BACKEND=hyprlock.
EOF
    exit 0
    ;;
  *)
    echo "lock-screen.sh: unknown option: $1" >&2
    exit 2
    ;;
esac

# Never stack two lock surfaces.
if pgrep -x hyprlock >/dev/null 2>&1 || pgrep -x swaylock >/dev/null 2>&1; then
  exit 0
fi

lock_with_swaylock() {
  local background_image=""

  if command -v swaylock >/dev/null 2>&1; then
    background_image=$("$HOME/.local/bin/lock-background.sh" 2>/dev/null || true)
    if [[ -n $background_image ]]; then
      exec swaylock -f -i "$background_image" -s fill
    fi
    exec swaylock -f
  fi

  echo "lock-screen.sh: swaylock is not available" >&2
  exit 1
}

if [[ $backend == hyprlock ]] && command -v hyprlock >/dev/null 2>&1 && [[ -f $hypr_config ]]; then
  if [[ $mode == background ]]; then
    setsid -f hyprlock --config "$hypr_config" --immediate-render --grace 0 \
      >"$log_file" 2>&1 </dev/null || true

    # Give hyprlock time to acquire the session lock before swayidle suspends.
    for _ in {1..20}; do
      pgrep -x hyprlock >/dev/null 2>&1 && break
      sleep 0.05
    done

    if pgrep -x hyprlock >/dev/null 2>&1; then
      sleep 0.35
      if pgrep -x hyprlock >/dev/null 2>&1; then
        exit 0
      fi
    fi

    echo "lock-screen.sh: hyprlock failed to start, falling back to swaylock" >&2
    lock_with_swaylock
  fi

  exec hyprlock --config "$hypr_config" --immediate-render --grace 0
fi

lock_with_swaylock
