#!/usr/bin/env bash
# Print the absolute path of the active wallpaper.
# Used by hyprlock's background { reload_cmd = ... }.

set -uo pipefail

find_swaybg_wallpaper() {
  local pid cwd candidate i
  local -a args

  while IFS= read -r pid; do
    [[ -n $pid ]] || continue
    cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)
    mapfile -d '' -t args < "/proc/$pid/cmdline" 2>/dev/null || continue

    for ((i = 0; i < ${#args[@]}; i++)); do
      case ${args[i]} in
        -i | --image)
          candidate=${args[i + 1]:-}
          [[ -n $candidate ]] || continue
          if [[ $candidate != /* && -n $cwd ]]; then
            candidate="$cwd/$candidate"
          fi
          if [[ -f $candidate ]]; then
            realpath -- "$candidate"
            return 0
          fi
          ;;
      esac
    done
  done < <(pgrep -x swaybg 2>/dev/null || true)

  return 1
}

find_cached_wallpaper() {
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-picker/last"
  local path

  [[ -s $cache ]] || return 1
  IFS= read -r path <"$cache" || true
  [[ -n ${path:-} && -f $path ]] || return 1
  realpath -- "$path"
}

find_swaybg_wallpaper || find_cached_wallpaper || {
  for path in \
    "$HOME/Pictures/Wallpapers/default.jpg" \
    "$HOME/Pictures/Wallpapers/lockscreen.jpg"; do
    if [[ -f $path ]]; then
      realpath -- "$path"
      exit 0
    fi
  done

  exit 1
}
