#!/usr/bin/env bash
# Print a lock-screen background derived from the active wallpaper.
# The image is blurred and darkened once, then cached by wallpaper mtime/size.

set -euo pipefail

wallpaper=$("$HOME/.local/bin/current-wallpaper.sh" 2>/dev/null || true)
[[ -n $wallpaper ]] || exit 1

if ! command -v ffmpeg >/dev/null 2>&1; then
  printf '%s\n' "$wallpaper"
  exit 0
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/lock-screen"
if ! mkdir -p "$cache_dir" 2>/dev/null; then
  printf '%s\n' "$wallpaper"
  exit 0
fi

digest=$(
  {
    printf 'lock-bg-v1\n'
    printf '%s\n' "$wallpaper"
    stat -c '%Y:%s' "$wallpaper" 2>/dev/null || true
  } | sha256sum | cut -d' ' -f1
)
processed="$cache_dir/background-$digest.png"

if [[ ! -s $processed ]]; then
  tmp=$(mktemp "$cache_dir/background-XXXXXX.png") || {
    printf '%s\n' "$wallpaper"
    exit 0
  }
  if ! ffmpeg -hide_banner -loglevel error -y -i "$wallpaper" \
    -vf "scale=2560:1440:force_original_aspect_ratio=increase,crop=2560:1440,gblur=sigma=24,eq=brightness=-0.12:saturation=0.70,drawbox=c=0x2a1738@0.68:t=fill" \
    -frames:v 1 "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    printf '%s\n' "$wallpaper"
    exit 0
  fi
  mv -f "$tmp" "$processed"
fi

printf '%s\n' "$processed"
