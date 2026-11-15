#!/usr/bin/env bash
#
# my-mango installer
#
# Раскладывает конфиги, скрипты и обои, ставит пакеты из packages.txt.
# Ничего не удаляет: существующие файлы сначала попадают в ~/.dotfiles-backup.
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/config"
BIN_SRC="$SCRIPT_DIR/local/bin"
SYSTEM_SRC="$SCRIPT_DIR/system"
WALLPAPERS_SRC="$SCRIPT_DIR/wallpapers"
PACKAGES_FILE="$SCRIPT_DIR/packages.txt"
BACKUP_ROOT="$HOME/.dotfiles-backup"

ASSUME_YES=0
DRY_RUN=0
INSTALL_PKGS=1
USE_AUR=1
NO_SYSTEM_SERVICES=0
FAILURES=0
BACKUP_DIR=""

OPT_CORE=""
OPT_CONFIGS=""
OPT_WALLPAPERS=""
OPT_USER_SERVICES=""
OPT_APPS=""
OPT_SYSTEM=""
OPT_PLYMOUTH=""
OPT_FLATPAK=""

declare -a BOOTSTRAP_PKGS=()
declare -a CORE_PKGS=()
declare -a CORE_AUR=()
declare -a APPS=()
declare -a APPS_AUR=()
declare -a SYSTEM_PKGS=()
declare -a SYSTEM_AUR=()
declare -a FLATPAK_APPS=()
declare -a SERVICES=()
declare -a USER_SERVICES=()

info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
my-mango installer

Использование:
  ./install.sh [опции]

Без опций запускается интерактивный режим: скрипт спрашивает,
что установить, и показывает итоговый план.

Опции:
  --with-apps        установить пакеты из [apps] и [apps-aur]
  --with-system      системные файлы и сервисы
  --with-plymouth    добавить hook plymouth и пересобрать initramfs
                     (включает --with-system)
  --with-flatpak     установить flatpak-приложения
  --all              всё перечисленное выше
  --no-packages      не устанавливать пакеты (только файлы)
  --no-aur           не использовать AUR (yay)
  --no-configs       не копировать конфиги и скрипты
  --no-services      не включать systemd-сервисы
  --no-wallpapers    не копировать обои
  --dry-run          показать действия, ничего не менять
  -y, --yes          не задавать вопросов, использовать дефолты
  -h, --help         эта справка

Примеры:
  ./install.sh
  ./install.sh --with-apps --with-system --with-plymouth --with-flatpak
  ./install.sh --all --dry-run
  ./install.sh --yes --with-system
EOF
}

ask_yes_no() {
  local prompt="$1" default="${2:-no}" answer
  while true; do
    if [[ "$default" == yes ]]; then
      read -r -p "$prompt [Y/n] " answer || answer=""
    else
      read -r -p "$prompt [y/N] " answer || answer=""
    fi
    answer="${answer,,}"
    case "$answer" in
      "")
        if [[ "$default" == yes ]]; then return 0; else return 1; fi
        ;;
      y|yes|д|да) return 0 ;;
      n|no|н|нет) return 1 ;;
      *) warn "Ответь yes/no (y/n)." ;;
    esac
  done
}

prompt_group() {
  local var="$1" prompt="$2" default="$3"
  if [[ -n "${!var:-}" ]]; then
    return 0
  fi
  if ask_yes_no "$prompt" "$default"; then
    printf -v "$var" '%s' yes
  else
    printf -v "$var" '%s' no
  fi
}

parse_args() {
  while (( $# )); do
    case "$1" in
      -y|--yes) ASSUME_YES=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --all)
        OPT_CORE=yes
        OPT_CONFIGS=yes
        OPT_WALLPAPERS=yes
        OPT_USER_SERVICES=yes
        OPT_APPS=yes
        OPT_SYSTEM=yes
        OPT_PLYMOUTH=yes
        OPT_FLATPAK=yes
        ;;
      --with-apps) OPT_APPS=yes ;;
      --with-system) OPT_SYSTEM=yes ;;
      --with-plymouth) OPT_PLYMOUTH=yes; OPT_SYSTEM=yes ;;
      --with-flatpak) OPT_FLATPAK=yes ;;
      --no-packages) INSTALL_PKGS=0 ;;
      --no-aur) USE_AUR=0 ;;
      --no-configs) OPT_CONFIGS=no ;;
      --no-services) OPT_USER_SERVICES=no; NO_SYSTEM_SERVICES=1 ;;
      --no-wallpapers) OPT_WALLPAPERS=no ;;
      -h|--help) usage; exit 0 ;;
      *) die "Неизвестный аргумент: $1 (см. --help)" ;;
    esac
    shift
  done
}

parse_packages() {
  [[ -f "$PACKAGES_FILE" ]] || die "Не найден $PACKAGES_FILE"

  local raw line section=""
  while IFS= read -r raw; do
    line="${raw%%#*}"
    line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
      section="${BASH_REMATCH[1]}"
      continue
    fi

    case "$section" in
      bootstrap) BOOTSTRAP_PKGS+=("$line") ;;
      core) CORE_PKGS+=("$line") ;;
      core-aur) CORE_AUR+=("$line") ;;
      apps) APPS+=("$line") ;;
      apps-aur) APPS_AUR+=("$line") ;;
      system) SYSTEM_PKGS+=("$line") ;;
      system-aur) SYSTEM_AUR+=("$line") ;;
      flatpak) FLATPAK_APPS+=("$line") ;;
      services) SERVICES+=("$line") ;;
      user-services) USER_SERVICES+=("$line") ;;
      *) warn "Неизвестная секция в packages.txt: $section" ;;
    esac
  done < "$PACKAGES_FILE"
}

resolve_choices() {
  if [[ "$OPT_PLYMOUTH" == yes ]]; then
    OPT_SYSTEM=yes
  fi

  if (( ASSUME_YES || DRY_RUN )); then
    : "${OPT_CORE:=yes}"
    : "${OPT_CONFIGS:=yes}"
    : "${OPT_WALLPAPERS:=yes}"
    : "${OPT_USER_SERVICES:=yes}"
    : "${OPT_APPS:=no}"
    : "${OPT_SYSTEM:=no}"
    : "${OPT_PLYMOUTH:=no}"
    : "${OPT_FLATPAK:=no}"
  else
    prompt_group OPT_CORE "Установить core-пакеты?" yes
    prompt_group OPT_CONFIGS "Скопировать конфиги и скрипты?" yes
    prompt_group OPT_WALLPAPERS "Скопировать обои?" yes
    prompt_group OPT_USER_SERVICES "Включить user-сервисы (mako/pipewire)?" yes
    prompt_group OPT_APPS "Установить optional apps?" no
    prompt_group OPT_SYSTEM "Настроить систему (файлы, сервисы)?" no
    if [[ "$OPT_SYSTEM" == yes ]]; then
      prompt_group OPT_PLYMOUTH "Пересобрать initramfs с Plymouth?" no
    fi
    prompt_group OPT_FLATPAK "Установить flatpak-приложения?" no
  fi

  if [[ "$OPT_SYSTEM" != yes ]]; then
    OPT_PLYMOUTH=no
  fi
}

print_plan() {
  info "План установки:"
  printf '  %-24s %s\n' "core packages:" "$OPT_CORE"
  printf '  %-24s %s\n' "configs + scripts:" "$OPT_CONFIGS"
  printf '  %-24s %s\n' "wallpapers:" "$OPT_WALLPAPERS"
  printf '  %-24s %s\n' "user services:" "$OPT_USER_SERVICES"
  printf '  %-24s %s\n' "optional apps:" "$OPT_APPS"
  printf '  %-24s %s\n' "system files:" "$OPT_SYSTEM"
  printf '  %-24s %s\n' "plymouth/initramfs:" "$OPT_PLYMOUTH"
  printf '  %-24s %s\n' "flatpak apps:" "$OPT_FLATPAK"

  if (( ! INSTALL_PKGS )); then
    printf '  %-24s %s\n' "package install:" "disabled (--no-packages)"
  fi
  if (( ! USE_AUR )); then
    printf '  %-24s %s\n' "AUR:" "disabled (--no-aur)"
  fi
  if (( DRY_RUN )); then
    printf '  %-24s %s\n' "mode:" "DRY RUN"
  fi
}

confirm_plan() {
  if (( ASSUME_YES || DRY_RUN )); then
    return 0
  fi
  if ! ask_yes_no "Продолжить?" yes; then
    info "Отменено."
    exit 0
  fi
}

run() {
  if (( DRY_RUN )); then
    printf '  [dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

backup_file() {
  local src="$1" new="${2:-}"
  [[ -e "$src" || -L "$src" ]] || return 0
  (( DRY_RUN )) && return 0

  # Если устанавливаемый файл уже совпадает с текущим, бэкап не нужен.
  if [[ -n "$new" ]]; then
    if [[ -f "$src" && -f "$new" ]] && cmp -s "$src" "$new"; then
      return 0
    fi
    if [[ -d "$src" && -d "$new" ]] && diff -rq "$src" "$new" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if [[ -z "$BACKUP_DIR" ]]; then
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
  fi

  local rel="${src#/}"
  local dest="$BACKUP_DIR/$rel"

  # Не плодим бэкапы, если содержимое уже совпадает.
  if [[ -f "$src" && -f "$dest" ]] && cmp -s "$src" "$dest"; then
    return 0
  fi
  if [[ -d "$src" && -d "$dest" ]] && diff -rq "$src" "$dest" >/dev/null 2>&1; then
    return 0
  fi

  # Бэкап всегда пишем от текущего пользователя: источники (/etc, /usr/share)
  # доступны на чтение, а каталог ~/.dotfiles-backup не должен принадлежать root.
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

install_pacman() {
  local -a pkgs=("$@")
  (( ${#pkgs[@]} )) || return 0

  if (( ! INSTALL_PKGS )); then
    warn "Установка пакетов отключена; пропускаю: ${pkgs[*]}"
    return 0
  fi

  if (( ! DRY_RUN )); then
    sudo -v || return 1
  fi
  run sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

install_yay() {
  local -a pkgs=("$@")
  (( ${#pkgs[@]} )) || return 0

  if (( ! USE_AUR )); then
    warn "AUR отключён; пропускаю: ${pkgs[*]}"
    return 0
  fi

  if (( DRY_RUN )); then
    printf '  [dry-run] yay -S --needed --noconfirm %s\n' "${pkgs[*]}"
    return 0
  fi

  if ! command -v yay >/dev/null 2>&1; then
    warn "yay не найден; пропускаю AUR: ${pkgs[*]}"
    return 1
  fi

  run yay -S --needed --noconfirm "${pkgs[@]}"
}

ensure_yay() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi

  if (( ! USE_AUR || ! INSTALL_PKGS )); then
    return 1
  fi

  warn "yay не найден."

  if (( ! ASSUME_YES && ! DRY_RUN )); then
    if ! ask_yes_no "Собрать yay из AUR?" yes; then
      USE_AUR=0
      warn "AUR отключён."
      return 1
    fi
  fi

  if (( DRY_RUN )); then
    info "[dry-run] сборка yay из AUR"
    return 0
  fi

  sudo -v || return 1
  sudo pacman -S --needed --noconfirm base-devel git || return 1

  local tmp rc=0
  tmp="$(mktemp -d)" || return 1
  if ! git clone https://aur.archlinux.org/yay.git "$tmp/yay"; then
    rm -rf "$tmp"
    return 1
  fi
  (cd "$tmp/yay" && makepkg -si --noconfirm) || rc=$?
  rm -rf "$tmp"
  return "$rc"
}

install_package_groups() {
  if (( ! INSTALL_PKGS )); then
    info "Установка пакетов пропущена (--no-packages)."
    return 0
  fi

  if [[ "$OPT_CORE" == yes ]]; then
    info "Core-пакеты (pacman)..."
    install_pacman "${CORE_PKGS[@]}" || FAILURES=$((FAILURES + 1))

    if (( USE_AUR )) && (( ${#CORE_AUR[@]} )); then
      info "Core-пакеты (AUR)..."
      if ensure_yay; then
        install_yay "${CORE_AUR[@]}" || FAILURES=$((FAILURES + 1))
      else
        warn "AUR-часть core пропущена."
      fi
    fi
  fi

  if [[ "$OPT_APPS" == yes ]]; then
    info "Optional apps (pacman)..."
    install_pacman "${APPS[@]}" || FAILURES=$((FAILURES + 1))

    if (( USE_AUR )) && (( ${#APPS_AUR[@]} )); then
      info "Optional apps (AUR)..."
      if ensure_yay; then
        install_yay "${APPS_AUR[@]}" || FAILURES=$((FAILURES + 1))
      else
        warn "AUR-часть apps пропущена."
      fi
    fi
  fi

  if [[ "$OPT_SYSTEM" == yes ]]; then
    info "Системные пакеты (pacman)..."
    install_pacman "${SYSTEM_PKGS[@]}" || FAILURES=$((FAILURES + 1))

    if (( USE_AUR )) && (( ${#SYSTEM_AUR[@]} )); then
      info "Системные пакеты (AUR)..."
      if ensure_yay; then
        install_yay "${SYSTEM_AUR[@]}" || FAILURES=$((FAILURES + 1))
      else
        warn "AUR-часть system пропущена."
      fi
    fi
  fi
}

copy_configs() {
  info "Копирую конфиги и скрипты..."
  run mkdir -p "$HOME/.config" "$HOME/.local/bin"

  local item name
  for item in "$CONFIG_SRC"/*; do
    [[ -e "$item" ]] || continue
    name="${item##*/}"
    backup_file "$HOME/.config/$name" "$item"
    run cp -a "$item" "$HOME/.config/"
  done

  for item in "$BIN_SRC"/*; do
    [[ -e "$item" ]] || continue
    name="${item##*/}"
    backup_file "$HOME/.local/bin/$name" "$item"
    run install -m 755 "$item" "$HOME/.local/bin/$name"
  done
}

copy_wallpapers() {
  info "Копирую обои..."
  local dest="$HOME/Pictures/Wallpapers"
  run mkdir -p "$dest"

  local f name
  for f in "$WALLPAPERS_SRC"/*; do
    [[ -e "$f" ]] || continue
    name="${f##*/}"
    if [[ -e "$dest/$name" ]]; then
      info "Уже есть, не трогаю: $name"
      continue
    fi
    run cp -a "$f" "$dest/$name"
  done
}

set_wallpaper_config() {
  local wp="$HOME/Pictures/Wallpapers/wp12478902-pink-and-purple-4k-wallpapers.jpg"
  if [[ ! -f "$wp" ]]; then
    wp="$HOME/Pictures/Wallpapers/default.jpg"
  fi
  if [[ ! -f "$wp" ]]; then
    warn "Обои не найдены; mango/wallpaper.conf оставлен как есть."
    return 0
  fi

  local conf="$HOME/.config/mango/wallpaper.conf"
  if (( DRY_RUN )); then
    printf '  [dry-run] write %s -> swaybg -i %s\n' "$conf" "$wp"
    return 0
  fi
  printf 'exec_once=swaybg -i %s\n' "$wp" > "$conf"
}

set_gsetting() {
  local schema="$1" key="$2" value="$3"
  if (( DRY_RUN )); then
    printf '  [dry-run] gsettings set %s %s %s\n' "$schema" "$key" "$value"
    return 0
  fi
  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings не найден; настройки GTK/курсора пропущены."
    return 0
  fi
  if ! gsettings set "$schema" "$key" "$value" 2>/dev/null; then
    warn "gsettings: не удалось $schema $key $value"
  fi
}

configure_gsettings() {
  info "Настраиваю GTK-тему и курсор..."
  set_gsetting org.gnome.desktop.interface gtk-theme Adwaita-dark
  set_gsetting org.gnome.desktop.interface color-scheme prefer-dark
  set_gsetting org.gnome.desktop.interface cursor-theme Sweet-cursors
  set_gsetting org.gnome.desktop.interface cursor-size 24
}

enable_user_services() {
  info "Включаю user-сервисы..."
  if (( DRY_RUN )); then
    local unit
    for unit in "${USER_SERVICES[@]}"; do
      printf '  [dry-run] systemctl --user enable --now %s\n' "$unit"
    done
    return 0
  fi

  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    warn "Нет активной user-сессии; включи вручную:"
    warn "  systemctl --user enable --now ${USER_SERVICES[*]}"
    return 0
  fi

  local unit
  for unit in "${USER_SERVICES[@]}"; do
    if systemctl --user cat "$unit" >/dev/null 2>&1; then
      if ! systemctl --user enable --now "$unit"; then
        warn "Не удалось включить $unit"
      fi
    else
      warn "user unit не найден: $unit"
    fi
  done

  if systemctl --user is-active --quiet mako.service 2>/dev/null; then
    makoctl reload >/dev/null 2>&1 || true
  fi
}

install_system_file() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || return 0
  backup_file "$dest" "$src"
  run sudo install -Dm644 "$src" "$dest"
}

enable_system_services() {
  info "Включаю системные сервисы..."
  local unit
  for unit in "${SERVICES[@]}"; do
    if systemctl cat "$unit" >/dev/null 2>&1; then
      if ! run sudo systemctl enable --now "$unit"; then
        warn "Не удалось включить $unit"
      fi
    else
      warn "system unit не найден: $unit"
    fi
  done
}

check_locale() {
  if ! locale -a 2>/dev/null | grep -qi '^en_US\.utf8$'; then
    warn "locale en_US.UTF-8 не сгенерирован."
    warn "Добавь en_US.UTF-8 в /etc/locale.gen и выполни: sudo locale-gen"
  fi
}

install_system_stage() {
  info "Системные файлы..."
  if (( ! DRY_RUN )); then
    sudo -v || die "Для системного этапа нужен sudo."
  fi

  install_system_file "$SYSTEM_SRC/etc/sddm.conf.d/sddm.conf" /etc/sddm.conf.d/sddm.conf
  install_system_file "$SYSTEM_SRC/etc/plymouth/plymouthd.conf" /etc/plymouth/plymouthd.conf
  install_system_file "$SYSTEM_SRC/etc/systemd/zram-generator.conf" /etc/systemd/zram-generator.conf
  install_system_file "$SYSTEM_SRC/etc/locale.conf" /etc/locale.conf
  install_system_file "$SYSTEM_SRC/etc/vconsole.conf" /etc/vconsole.conf

  if (( ! NO_SYSTEM_SERVICES )); then
    enable_system_services
  fi

  check_locale
}

install_plymouth() {
  info "Настраиваю Plymouth..."
  if ! command -v mkinitcpio >/dev/null 2>&1; then
    warn "mkinitcpio не найден; пропускаю."
    return 0
  fi

  if ! grep -qw splash /proc/cmdline 2>/dev/null; then
    warn "В /proc/cmdline нет splash; добавь splash в параметры ядра."
  fi

  local conf=/etc/mkinitcpio.conf
  if ! grep -qE '^HOOKS=.*\bplymouth\b' "$conf" 2>/dev/null; then
    backup_file "$conf"
    if grep -qE '^HOOKS=.*\budev\b' "$conf" 2>/dev/null; then
      run sudo sed -i -E 's/^(HOOKS=\([^)]*)\budev\b/\1udev plymouth/' "$conf"
    elif grep -qE '^HOOKS=.*\bsystemd\b' "$conf" 2>/dev/null; then
      run sudo sed -i -E 's/^(HOOKS=\([^)]*)\bsystemd\b/\1systemd plymouth/' "$conf"
    else
      warn "Не нашёл udev/systemd в HOOKS; добавь plymouth вручную."
    fi
  fi

  if (( DRY_RUN )); then
    run sudo mkinitcpio -P
  elif grep -qE '^HOOKS=.*\bplymouth\b' "$conf"; then
    run sudo mkinitcpio -P
  else
    warn "Hook plymouth не добавлен; initramfs не пересобираю."
  fi
}

install_flatpak_apps() {
  info "Flatpak-приложения..."
  if (( ! INSTALL_PKGS )); then
    warn "--no-packages: flatpak пропущен."
    return 0
  fi

  if ! command -v flatpak >/dev/null 2>&1; then
    install_pacman flatpak || return 1
  fi

  if ! run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
    warn "Не удалось добавить flathub."
    return 1
  fi

  local app
  for app in "${FLATPAK_APPS[@]}"; do
    if ! run flatpak install -y flathub "$app"; then
      warn "Не удалось установить flatpak: $app"
      FAILURES=$((FAILURES + 1))
    fi
  done
}

main() {
  parse_args "$@"

  if (( EUID == 0 )); then
    die "Не запускай от root: скрипт сам вызывает sudo там, где нужно."
  fi
  if [[ ! -f /etc/arch-release ]]; then
    die "Этот установщик рассчитан на Arch Linux (/etc/arch-release не найден)."
  fi
  if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
    die "HOME не задан или не существует."
  fi

  parse_packages
  resolve_choices
  print_plan
  confirm_plan

  install_package_groups

  if [[ "$OPT_CONFIGS" == yes ]]; then
    copy_configs
  fi

  if [[ "$OPT_WALLPAPERS" == yes ]]; then
    copy_wallpapers
  fi

  if [[ "$OPT_CONFIGS" == yes ]]; then
    set_wallpaper_config
    configure_gsettings
  fi

  if [[ "$OPT_USER_SERVICES" == yes ]]; then
    enable_user_services
  fi

  if [[ "$OPT_SYSTEM" == yes ]]; then
    install_system_stage
  fi

  if [[ "$OPT_PLYMOUTH" == yes ]]; then
    install_plymouth
  fi

  if [[ "$OPT_FLATPAK" == yes ]]; then
    install_flatpak_apps || FAILURES=$((FAILURES + 1))
  fi

  if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
    info "Бэкап: $BACKUP_DIR"
  fi

  if (( FAILURES > 0 )); then
    warn "Завершено с ошибками: $FAILURES. Проверь вывод выше."
    exit 1
  fi

  if (( DRY_RUN )); then
    info "DRY RUN завершён: изменения не применялись."
  else
    info "Готово."
    if [[ "$OPT_SYSTEM" == yes || "$OPT_PLYMOUTH" == yes ]]; then
      info "Для SDDM/Plymouth/zram может понадобиться перезагрузка."
    fi
  fi
}

main "$@"
