# my-mango

my personal arch linux setup built around mangowm, waybar, foot, mako, swaylock, swayidle and a bunch of other stuff.

this thing was made with ai assistance, so don't expect perfection. i use it on my own machine, and it works for me. that's pretty much the extent of my quality assurance.

if you somehow stumbled upon this repo and decided to use it: **i take absolutely no responsibility for whatever happens to your system.** use at your own risk, read the scripts before running them, and maybe don't blindly trust random stuff you find on github. including this one.

the installer backs up existing files to `~/.dotfiles-backup/<date>/` before replacing them. at least it tries not to ruin your day.

## installer

```bash
git clone <repo-url> my-mango
cd my-mango
./install.sh
```

run without arguments to choose what to install interactively.

### flags

| flag | description |
|---|---|
| `--all` | install everything |
| `--with-apps` | install optional apps and aur packages |
| `--with-system` | install system files, themes and system services |
| `--with-plymouth` | configure plymouth and rebuild initramfs |
| `--with-flatpak` | install flatpak apps |
| `--no-packages` | skip package installation |
| `--no-aur` | skip aur packages |
| `--no-configs` | skip configs and scripts |
| `--no-services` | skip systemd services |
| `--no-wallpapers` | skip wallpapers |
| `--dry-run` | preview changes without applying them |
| `-y`, `--yes` | skip prompts and use defaults |

## contents

- mangowm and waybar configs
- foot, fish, mako, swaylock, swayidle, waypaper configs
- personal scripts
- sddm and plymouth themes
- wallpapers
- package list (official repos, aur, flatpak)
- a few system tweaks
