# Waybar: вертикальный бар для Mango

Конфиг лежит в `config/waybar` и копируется в `~/.config/waybar` скриптом
`install.sh` из корня репозитория. Отдельно копировать файлы не нужно.

## Зависимости

- `waybar` (проверено на 0.16.0)
- `fuzzel` — лаунчер и меню выбора; `rofi` — запасной вариант
- `powerprofilesctl` — меню power profile
- `brightnessctl` — яркость
- `wpctl` (PipeWire) — громкость
- `swaybg` — смена обоев
- `python-gobject` + GTK 3 — галерея обоев
- `blueman` — меню Bluetooth
- `nm-connection-editor` — настройка сети
- `~/.local/bin/launcher.sh` — лаунчер (fuzzel)
- шрифт `JetBrainsMono Nerd Font`

## Замечания

- Воркспейсы сделаны через `ext/workspaces`. В waybar 0.16 уже есть нативные
  `mango/workspaces`, `mango/language`, `mango/layout`, но текущий вариант
  проверен и оставлен как есть.
- Размытие обеспечивает сам Mango: в `~/.config/mango/appearance.conf`
  должно быть `blur_layer=1`. CSS задаёт только полупрозрачный фон.
- Ширина бара — 60 px; при другом шрифте/размере waybar может увеличить
  ширину под содержимое.
- Клик по логотипу Arch открывает `~/.local/bin/launcher.sh`.
- Клик по иконке обоев открывает галерею с превью всех изображений из
  `~/Pictures/Wallpapers`. Выбор — Enter или клик, закрытие — Esc,
  правый клик или кнопка «Закрыть». Каталог можно переопределить
  переменной `WALLPAPER_DIR`.
- Клик по батарее открывает меню power profile (fuzzel, запасной вариант — rofi).
- Прокрутка на громкости меняет громкость, на яркости — яркость.
- Клик по Bluetooth открывает `blueman-manager`.
- Клик по Wi-Fi открывает `nm-connection-editor`.
