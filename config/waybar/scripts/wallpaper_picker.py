#!/usr/bin/env python3

import hashlib
import os
import shlex
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango


WALL_DIR = Path(os.environ.get("WALLPAPER_DIR", Path.home() / "Pictures/Wallpapers")).expanduser()
THUMB_W = 300
THUMB_H = 169
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
THUMB_VERSION = 1
THUMB_WORKERS = 4
CACHE_DIR = Path(GLib.get_user_cache_dir()) / "wallpaper-picker" / "thumbs"

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


def cache_path_for(path):
    try:
        stat = path.stat()
        resolved = path.resolve()
    except (OSError, RuntimeError):
        return None
    raw = (
        f"v{THUMB_VERSION}\0{resolved}\0{stat.st_mtime_ns}\0{stat.st_size}"
        f"\0{THUMB_W}x{THUMB_H}"
    )
    digest = hashlib.sha1(raw.encode("utf-8", "surrogateescape")).hexdigest()
    return CACHE_DIR / f"{digest}.jpg"


def load_cached_thumb(path):
    cache = cache_path_for(path)
    if cache is None or not cache.is_file():
        return None
    try:
        return GdkPixbuf.Pixbuf.new_from_file(str(cache))
    except GLib.Error:
        try:
            cache.unlink()
        except OSError:
            pass
        return None


def make_thumb(path):
    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(path), THUMB_W, THUMB_H, True)
    cache = cache_path_for(path)
    if cache is None:
        return pixbuf

    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(
            prefix=cache.stem + ".", suffix=".tmp", dir=CACHE_DIR
        )
        os.close(fd)
    except OSError:
        return pixbuf

    try:
        pixbuf.savev(tmp_name, "jpeg", ["quality"], ["85"])
        os.replace(tmp_name, cache)
    except (GLib.Error, OSError):
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
    return pixbuf


def make_placeholder():
    pixbuf = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, THUMB_W, THUMB_H)
    pixbuf.fill(0x241F2A)
    return pixbuf


def check_thumbs(wallpapers):
    cached = 0
    missing = []
    for path in wallpapers:
        if load_cached_thumb(path) is not None:
            cached += 1
        else:
            missing.append(path)

    generated = 0
    if missing:
        workers = min(THUMB_WORKERS, len(missing))
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [executor.submit(make_thumb, path) for path in missing]
            for future in futures:
                try:
                    future.result()
                    generated += 1
                except (GLib.Error, OSError):
                    pass
    return cached + generated


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
    try:
        wallpaper_conf.parent.mkdir(parents=True, exist_ok=True)
        wallpaper_conf.write_text(
            f"exec_once=swaybg -i {shlex.quote(str(path))}\n",
            encoding="utf-8",
        )
    except OSError:
        pass

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
        self._alive = True
        self._executor = None
        self._images = {}
        self._buttons = {}
        self._pending = []

        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.connect("destroy", self._on_destroy)
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
        except (OSError, RuntimeError):
            current_path = None

        placeholder = make_placeholder()

        for path in wallpapers:
            button = Gtk.Button()
            button.set_relief(Gtk.ReliefStyle.NONE)
            button.get_style_context().add_class("thumb")
            try:
                if current_path is not None and path.resolve() == current_path:
                    button.get_style_context().add_class("current")
            except (OSError, RuntimeError):
                pass

            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)

            image = Gtk.Image()
            image.set_size_request(THUMB_W, THUMB_H)
            image.set_halign(Gtk.Align.CENTER)
            pixbuf = load_cached_thumb(path)
            if pixbuf is not None:
                image.set_from_pixbuf(pixbuf)
            else:
                image.set_from_pixbuf(placeholder)
                self._pending.append(path)
            self._images[path] = image
            self._buttons[path] = button

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

    def start_loading(self):
        if not self._alive or not self._pending:
            return False
        paths = self._pending
        self._pending = []
        self._executor = ThreadPoolExecutor(max_workers=min(THUMB_WORKERS, len(paths)))
        for path in paths:
            future = self._executor.submit(make_thumb, path)
            future.add_done_callback(
                lambda done, item=path: GLib.idle_add(self._apply_thumb, item, done)
            )
        return False

    def _apply_thumb(self, path, future):
        if not self._alive:
            return False
        try:
            pixbuf = future.result()
        except (GLib.Error, OSError) as error:
            print(f"wallpaper-picker: cannot load {path}: {error}", file=sys.stderr)
            button = self._buttons.get(path)
            if button is not None:
                button.set_visible(False)
            return False
        image = self._images.get(path)
        if image is not None:
            image.set_from_pixbuf(pixbuf)
        return False

    def _on_destroy(self, *_args):
        self._alive = False
        if self._executor is not None:
            self._executor.shutdown(wait=False, cancel_futures=True)
            self._executor = None
        if Gtk.main_level() > 0:
            Gtk.main_quit()

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

    if "--check" in sys.argv[1:]:
        loaded = check_thumbs(wallpapers)
        print(f"ok: {loaded}/{len(wallpapers)} thumbnails loaded from {WALL_DIR}")
        return 0

    if not wallpapers:
        command = ["notify-send", "-a", "Wallpaper", f"No wallpapers found in {WALL_DIR}"]
        if subprocess.run(["which", "notify-send"], stdout=subprocess.DEVNULL).returncode == 0:
            subprocess.run(command, check=False)
        return 1

    picker = WallpaperPicker(wallpapers)
    picker.show_all()
    picker.present()
    picker.fullscreen()
    picker.focus_first()
    GLib.idle_add(picker.start_loading)
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
