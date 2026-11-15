# Шаги, которые нельзя автоматизировать

`install.sh` достраивает уже установленный Arch. Он не размечает диск, не
ставит bootloader и не переносит секреты. Ниже — что сделать руками.

## 1. Диск и fstab

Скрипт не трогает `/etc/fstab`. Если переустанавливаешь систему, создай
btrfs-сабволумы и пропиши их так же, как было. Пример структуры:

```text
@          /
@home      /home
@snapshots /.snapshots
@var_cache /var/cache
@var_log   /var/log
/boot      FAT32, UUID раздела
```

UUID после переустановки могут измениться. Сверяйся с `lsblk -f`.

## 2. Bootloader и параметры ядра

Используется systemd-boot. Записи лежат в `/boot/loader/entries/`, их нужно
создать заново. В параметрах ядра должны быть:

```text
root=PARTUUID=... zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs quiet splash
```

`quiet splash` нужны для Plymouth. Если `splash` нет, тема установится, но
загрузка будет текстовой.

## 3. Hostname и locale

```bash
sudo hostnamectl set-hostname arch
```

`/etc/locale.conf`, `/etc/vconsole.conf` копируются скриптом. Если `en_US.UTF-8`
не сгенерирован:

```bash
sudo sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sudo locale-gen
```

## 4. Timeshift

`/etc/timeshift/timeshift.json` не копируется: там UUID диска. Настрой
Timeshift заново через GUI или создай конфиг под свой диск.

## 5. Plymouth

Скрипт с `--with-plymouth`:

- копирует тему `arch-mac-style`;
- добавляет hook `plymouth` в `/etc/mkinitcpio.conf`;
- выполняет `plymouth-set-default-theme -R arch-mac-style` (пересборка initramfs).

Если делал вручную, проверь:

```bash
grep '^HOOKS' /etc/mkinitcpio.conf
plymouth-set-default-theme -l
sudo plymouth-set-default-theme -R arch-mac-style
```

## 6. SDDM

Скрипт с `--with-system` копирует `/etc/sddm.conf.d/sddm.conf` и тему
`where_is_my_sddm_theme` в `/usr/share/sddm/themes/`. Проверка:

```bash
cat /etc/sddm.conf.d/sddm.conf
ls /usr/share/sddm/themes/where_is_my_sddm_theme
```

## 7. SKLauncher и Horizon

Их нет в репозитории из-за размера:

- `SKLauncher-*.AppImage` — положить в `~/.local/bin/` и сделать исполняемым;
- `horizon-launcher` — аналогично;
- `.desktop`-файлы при необходимости создать заново.

## 8. Что не переносится

- Профили Brave/Firefox (там cookies, пароли, история).
- SSH-ключи и `~/.ssh`.
- Keyrings, `~/.local/share/keyrings`.
- Cookies, `.cache`, логи.
- Виртуалки GNOME Boxes/libvirt.
- Настройки Minecraft.

Это лучше бэкапить отдельно и не хранить в публичном git.
