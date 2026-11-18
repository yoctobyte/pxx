# Path B: an X11 desktop compiled by pxx

This builds pixx's own desktop: the TinyX Xfbdev framebuffer X server, the dwm
window manager and the st terminal. Every C file, including the X libraries
(Xlib, xcb, Xft, fontconfig, freetype, expat, libXfont, zlib), is compiled
and linked by pxx. The binaries are static and use pxx's crtl, not glibc.

```
PATHB_WORK=/data/tmp/pathb-work tools/pathb/build.sh
```

The result is `$PATHB_WORK/bundle/pixx-pathb-desktop-x86_64.tar.gz`, a
root-relative tree, with its `.sha256` next to it. pixx pins that tarball.

## How it works

1. `fetch.sh` downloads the sources listed in `sources.lock` (URL + sha256).
2. `gccbuild.sh` builds everything once with gcc (`make -j1 V=1`, static).
   The make logs are the recipe: they hold every compile with its directory
   and flags. TinyX gets the patches in `patches/` first.
3. `replay-cc.py` replays each `gcc -c` from those logs through
   `pxx --emit-obj` with `$PXXFLAGS` (default `--shared-runtime
   --threadsafe`).
4. `link.sh` links st, dwm and Xfbdev with `pxx --link` from those objects:
   - `libobjs.py` maps a gcc archive's members to their replay objects.
   - `xfb_objs.py` collects the objects on gcc's Xfbdev link line.
   - `drop_dups.py` pulls library members by ld's archive rule.
   It also builds gcc versions of st and dwm (`bin/*_gcc`) for comparison.
5. `lvgl.sh` builds LVGL 9.2.2's widgets demo with pxx as `bin/lvgl-demo`:
   no X server, it draws straight into `/dev/fb0`. Set
   `LV_EVDEV=/dev/input/eventN` for a pointer and `LV_FBDEV` for another
   framebuffer. Its `lv_conf.h` is LVGL's template with ten checked edits.
6. `make_bundle.sh` adds `files/startx-pixx`, `files/fonts.conf`, the core X
   fonts (built from the X.org BDF sources with `bdftopcf`), DejaVu, and
   every licence.

`qemu-test.sh KERNEL out.png` boots a Linux kernel (fbdev and devtmpfs
required) with busybox and the bundle. Its `/init` runs `startx-pixx`; the
script then types, moves the pointer and takes a screendump.

## Host requirements

gcc, autoconf/automake/libtool, make, python3, curl, bdftopcf, mkfontdir,
and a pxx compiler. For the test, also qemu-system-x86_64, a static busybox
and python3-PIL.

## Notes

- **TinyX licence:** the repository is GPLv3 as a whole, but its source
  files carry the original X11/MIT notices; the owner OK'd using it
  (2026-11-18). Everything else is MIT/X11, the FreeType licence, zlib or
  expat, plus the DejaVu licence. misc-fixed is public domain.
- **patches/tinyx-us-keymap-fallback.patch:** a built-in US keymap for
  consoles without KDGKBENT.
- **libXfont's `weak` fallbacks:** pxx reports `__GNUC__` 2.7, so
  libXfont's `weak` macro is empty and its fallbacks for server symbols come
  out strong. `drop_dups.py` makes the losing copies local, which is the same
  result as gcc's weak resolution.
- **LVGL demo:** in QEMU it is pixel-identical to a gcc build of the same
  sources, on the first screen and after a click on the Analytics tab.
- **Checked in QEMU on /dev/fb0:** the all-pxx stack is pixel-identical to
  the same clients on a gcc-built Xfbdev, and pxx's st and dwm match gcc's on
  Xvfb. Keyboard and mouse work.
