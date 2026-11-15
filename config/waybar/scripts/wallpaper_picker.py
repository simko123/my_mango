#!/usr/bin/env python3

import os
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango


WALL_DIR = Path(os.environ.get("WALLPAPER_DIR", Path.home() / "Pictures/Wallpapers")).expanduser()
THUMB_W = 300
THUMB_H = 169
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}

CSS = b"""
window {
  background-color: rgba(17, 14, 20, 0.96);
}

#panel {
  background-color: rgba(24, 20, 28, 0.92);
  border: 1px solid rgba(213, 190, 233, 0.22);
  border-radius: 24px;
}

#title {
  color: #e9e2f0;
  font-size: 22px;
  font-weight: 700;
}

#hint {
  color: rgba(233, 226, 240, 0.55);
  font-size: 12px;
}

button.close {
  background-color: rgba(255, 255, 255, 0.07);
  border: 1px solid rgba(213, 190, 233, 0.18);
  border-radius: 12px;
  color: #e9e2f0;
  font-size: 12px;
  padding: 7px 14px;
}

button.close:hover {
  background-color: rgba(249, 115, 134, 0.18);
  border-color: rgba(249, 115, 134, 0.45);
}

button.thumb {
  background-color: rgba(255, 255, 255, 0.05);
  border: 2px solid transparent;
  border-radius: 16px;
  padding: 8px;
}

button.thumb:hover {
  background-color: rgba(213, 190, 233, 0.12);
  border-color: rgba(213, 190, 233, 0.55);
}

button.thumb.current {
  border-color: #d5bee9;
}

button.thumb .caption {
  color: rgba(233, 226, 240, 0.72);
  font-size: 11px;
}

scrolledwindow,
viewport,
flowbox,
flowboxchild {
  background-color: transparent;
}
"""


def list_wallpapers():
    if not WALL_DIR.is_dir():
        return []
    return sorted(
        path
        for path in WALL_DIR.iterdir()
        if path.is_file() and path.suffix.lower() in IMAGE_EXTS
    )


def current_wallpaper():
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            cmd = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        if not cmd or os.path.basename(os.fsdecode(cmd[0])) != "swaybg":
            continue
        for index, arg in enumerate(cmd):
            if arg == b"-i" and index + 1 < len(cmd):
                return os.fsdecode(cmd[index + 1])
    return None


def apply_wallpaper(path):
    subprocess.run(
        ["pkill", "-x", "swaybg"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.Popen(
        ["swaybg", "-i", str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    wallpaper_conf = Path.home() / ".config/mango/wallpaper.conf"
    wallpaper_conf.parent.mkdir(parents=True, exist_ok=True)
    with wallpaper_conf.open("w", encoding="utf-8") as f:
        f.write(f"exec_once=swaybg -i {path}\n")

    cache_dir = Path(GLib.get_user_cache_dir()) / "wallpaper-picker"
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        (cache_dir / "last").write_text(f"{path}\n")
    except OSError:
        pass


class WallpaperPicker(Gtk.Window):
    def __init__(self, wallpapers):
        super().__init__(title="Обои")
        self.wallpapers = wallpapers
        self.loaded = 0

        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.connect("destroy", Gtk.main_quit)
        self.connect("key-press-event", self.on_key_press)
        self.connect("button-press-event", self.on_button_press)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_border_width(40)
        self.add(outer)

        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        panel.set_name("panel")
        panel.set_border_width(26)
        panel.set_hexpand(True)
        panel.set_vexpand(True)
        outer.pack_start(panel, True, True, 0)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        title = Gtk.Label(label="Обои")
        title.set_name("title")
        title.set_xalign(0.0)

        hint = Gtk.Label(label="Enter — выбрать · Esc / правый клик — закрыть")
        hint.set_name("hint")
        hint.set_xalign(1.0)
        hint.set_hexpand(True)

        close = Gtk.Button(label="Закрыть")
        close.set_relief(Gtk.ReliefStyle.NONE)
        close.get_style_context().add_class("close")
        close.connect("clicked", lambda *_: Gtk.main_quit())

        header.pack_start(title, False, False, 0)
        header.pack_start(hint, True, True, 0)
        header.pack_end(close, False, False, 0)
        panel.pack_start(header, False, False, 0)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_hexpand(True)
        scrolled.set_vexpand(True)
        panel.pack_start(scrolled, True, True, 0)

        self.flow = Gtk.FlowBox()
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_max_children_per_line(5)
        self.flow.set_selection_mode(Gtk.SelectionMode.NONE)
        self.flow.set_column_spacing(14)
        self.flow.set_row_spacing(14)
        scrolled.add(self.flow)

        current = current_wallpaper()
        try:
            current_path = Path(current).resolve() if current else None
        except OSError:
            current_path = None

        for path in wallpapers:
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    str(path), THUMB_W, THUMB_H, True
                )
            except GLib.Error:
                continue

            self.loaded += 1
            button = Gtk.Button()
            button.set_relief(Gtk.ReliefStyle.NONE)
            button.get_style_context().add_class("thumb")
            try:
                if current_path is not None and path.resolve() == current_path:
                    button.get_style_context().add_class("current")
            except OSError:
                pass

            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)

            image = Gtk.Image.new_from_pixbuf(pixbuf)
            image.set_size_request(THUMB_W, THUMB_H)
            image.set_halign(Gtk.Align.CENTER)

            caption = Gtk.Label(label=path.stem)
            caption.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
            caption.set_max_width_chars(34)
            caption.set_tooltip_text(path.name)
            caption.get_style_context().add_class("caption")

            content.pack_start(image, False, False, 0)
            content.pack_start(caption, False, False, 0)
            button.add(content)
            button.connect("clicked", self.on_choose, path)
            self.flow.add(button)

    def on_choose(self, _button, path):
        apply_wallpaper(path)
        Gtk.main_quit()

    def on_key_press(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            Gtk.main_quit()
            return True
        return False

    def on_button_press(self, _widget, event):
        if event.button == 3:
            Gtk.main_quit()
            return True
        return False

    def focus_first(self):
        child = self.flow.get_child_at_index(0)
        if child is not None:
            child.grab_focus()


def main():
    wallpapers = list_wallpapers()
    picker = WallpaperPicker(wallpapers)

    if "--check" in sys.argv[1:]:
        print(f"ok: {picker.loaded}/{len(wallpapers)} thumbnails loaded from {WALL_DIR}")
        return 0

    if picker.loaded == 0:
        command = ["notify-send", "-a", "Wallpaper", f"No wallpapers found in {WALL_DIR}"]
        if subprocess.run(["which", "notify-send"], stdout=subprocess.DEVNULL).returncode == 0:
            subprocess.run(command, check=False)
        return 1

    picker.show_all()
    picker.present()
    picker.fullscreen()
    picker.focus_first()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
