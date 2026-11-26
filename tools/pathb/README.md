# Path B: an X11 desktop compiled by pxx

This builds pixx's own desktop: two X servers, Xorg on Linux DRM (the
modesetting driver, evdev input) and the TinyX Xfbdev framebuffer server as
the fallback; the JWM window manager (dwm with `PIXX_WM=dwm`), the st
terminal, xclock, xcalc, xeyes, xload, xedit, xkbcomp and LVGL's framebuffer
demo. Every C file, the libraries included (Xlib, xcb, Xt, Xaw, Xmu, Xpm,
Xft, fontconfig, freetype, expat, libXfont, libXfont2, zlib, pixman,
libdrm, libevdev, mtdev, libxkbfile, libmd, libxcvt), is compiled and linked
by pxx. The binaries are static and use pxx's crtl, not glibc.

It builds in two places from one recipe:

- **On the host**, with gcc: `build.sh` records the recipe from a gcc
  reference build, then runs the target's own steps on it.
- **On site**, on the target, with only pxx, a POSIX shell and toybox-level
  tools: `onsite.sh` takes the recipe and the pinned source tarballs. That is
  Nodisx's install path: nothing but the bootstrap set is shipped as a binary.

Both produce `bundle/pixx-pathb-desktop-x86_64.tar.gz`, a root-relative tree
(pixx pins it), and `bundle/bundle.manifest`, the sha256 and mode of every
file in it. **Two builds agree when their manifests are identical.** The
tarball's own bytes depend on the tar and gzip that wrote it; GNU tar on the
host writes a reproducible one.

```
PATHB_WORK=/data/tmp/pathb-work tools/pathb/build.sh          # host
# target: the recipe dir, the tarballs from sources.lock, pxx on PATH
RECIPE=/x/recipe DL=/x/dl PXX=pxx sh /x/recipe/tools/onsite.sh /some/workdir
```

## The host side

1. `fetch.sh` downloads the sources in `sources.lock` (URL + sha256).
2. `gccbuild.sh` builds everything once with gcc (`make -j1 V=1`, static),
   configured for the target's layout (`--prefix=/usr`, `/etc`, `/var`) and
   installed with `DESTDIR` into `$PATHB_WORK/stage`, so every path compiled
   into a program is the target's. It applies `patches/NAME-*.patch` after
   unpacking. The make logs hold every compile with its directory and flags.
   The meson packages (libdrm, pixman, libxcvt, xkeyboard-config) are built
   with `ninja -v`, whose output is written as a make-style log. meson and
   ninja must be on `PATH` (a venv will do).
3. `prep.sh`: st's and dwm's `config.h`, and LVGL's `lv_conf.h` (its
   template with ten checked edits).
4. `fonts.sh`: the core X fonts, PCF from the X.org BDF sources (bdftopcf,
   ucs2any, mkfontdir are host tools, so the fonts travel as data).
5. `record.py` writes `$PATHB_WORK/recipe/`:
   - `sources.list`: source dir and tarball, unpacked with `--strip-components=1`;
   - `gen.tar.gz`: every file the gcc build generated or changed in the source
     trees (each `config.h`, xcb's generated C, the patched files...), the
     staged headers and run-time data, and `lv_conf.h`;
   - `compile.list`: one `pxx --emit-obj` per line, tab-separated
     (`PKG CWD OUT ARG...`), `@W@` standing for the work dir. Each one maps
     the work dir to `/usr/src/pathb` (`-ffile-prefix-map`), so the objects
     do not depend on where they were built;
   - `fonts/`, `tools/` (onsite.sh, make_bundle.sh and what they install),
     `RECIPE` (the pxx commit it was recorded with).
6. `onsite.sh WORK compile`: the target's compile stage, on the host.
7. `linkplan.sh` writes `recipe/link.list`, what every program links:
   - `libobjs.py` maps a gcc archive's members to their pxx objects;
   - `xfb_objs.py` collects the objects on gcc's Xfbdev link line;
   - `prog_objs.py` does the same for one program's gcc link line;
   - `arc_objs.py` maps the Xorg server's own archives (and the module
     archives) to their objects;
   - `drop_dups.py` pulls library members by ld's archive rule.
   It stops if a member would need `objcopy --localize-symbol`, since the
   target has none.
8. `onsite.sh WORK link bundle`: the target's last two stages.

## Xorg on DRM

- **Static, no dlopen.** pxx has no dynamic loader, so the modules Xorg
  would load (modesetting, shadow, evdev) are linked in.
  `patches/xorg-server-static-modules.patch` gives the loader a table of
  built-in modules, a weak empty one by default.
  `files/xorg-static-modules.c` is the strong table, compiled with
  loader.c's flags. `LoadModule` finds a module there before it searches
  the module path. fb, ddc, i2c, ramdac, dbe, record and extmod are already
  built into the server.
- **No udev, no PCI.** The server is configured without udev, HAL, logind,
  libpciaccess, int10, VGA hw, DGA, GLX, DRI1/DRI3 and glamor. DRI2 stays
  on, because modesetting needs it to build. Software rendering on dumb
  buffers only. `patches/xorg-server-modesetting-no-pci.patch` lets
  modesetting build without libpciaccess. It then probes through
  `Option "kmsdev"`. `patches/xf86-input-evdev-no-udev.patch` lets evdev
  configure without libudev.
- **startx-pixx** runs Xorg when `/dev/dri/card0` exists, and falls back to
  Xfbdev when Xorg does not start. `PIXX_X=xorg|xfbdev` forces one, and
  `PIXX_KMSDEV` picks another card. With no udev to add input devices, it
  writes `/tmp/xorg-pixx.conf`: one evdev InputDevice per keyboard, mouse
  and touchpad in `/proc/bus/input/devices` (pixx-desktop's
  classification), the layout `PIXX_XKBLAYOUT` (default `us`), and
  AutoAddDevices off. The log is `/tmp/Xorg.0.log`.
- **Keymaps:** the bundle ships xkbcomp and the xkeyboard-config data
  (`/usr/share/X11/xkb`, a data package: not compiled, not replayed).
  Compiled keymaps go to `/var/lib/xkb`.

## The on-site side

`onsite.sh WORKDIR [unpack|compile|link|bundle]...` (all four by default):
unpack the tarballs and lay `gen.tar.gz` over them, run `compile.list` with
`JOBS` jobs, run `link.list`, then `make_bundle.sh`. Tools: sh, tar, xzcat,
bzcat, zcat, gzip, sed, sort, grep, cut, find, stat, sha256sum, readlink,
cp, mv, chmod, mkdir, and pxx (with `PXX_HOME`). No gcc, make, autoconf,
python, patch, ar, nm or objcopy. Tested with dash, toybox 0.8.12, xzcat and
bzcat and nothing else on `PATH`. Most of the X.Org tarballs are old V7 tar
with no `ustar` magic, which toybox and GNU tar read and a busybox tar built
without its old-GNU compatibility option (Ubuntu's) refuses: "invalid tar
magic".

The recipe is tied to the pxx commit in `RECIPE`: `link.list` was computed
from that pxx's objects. A different pxx needs a new recording.

## Tests

`qemu-test.sh KERNEL out.png` boots a Linux kernel (fbdev and devtmpfs
required) with busybox and the bundle. Its `/init` runs `startx-pixx`; the
script then types, moves the pointer and takes a screendump. QEMU's
`-vga std` is bochs-drm: with that driver in the kernel, `/dev/dri/card0`
exists and the test runs Xorg, and Xorg's log is copied to the serial log
(`TAIL=N` shows its last N lines).

## Host requirements

gcc, autoconf/automake/libtool, make, python3, patch, curl, binutils (nm,
ar), bdftopcf, mkfontdir, ucs2any with font-util's `map-ISO8859-1`, meson
and ninja, pkg-config, and a pxx compiler. For the test, also qemu-system-x86_64, a static busybox and
python3-PIL.

## Notes

- **TinyX licence:** the repository is GPLv3 as a whole, but its source
  files carry the original X11/MIT notices; the owner OK'd using it
  (2026-11-18). Everything else is MIT/X11, the FreeType licence, zlib or
  expat, plus the DejaVu licence. misc-fixed is public domain.
- **patches/tinyx-us-keymap-fallback.patch:** a built-in US keymap for
  consoles without KDGKBENT.
- **patches/libXfont-weak-stubs.patch:** libXfont makes its fallbacks for
  server symbols `weak` only when `__GNUC__ >= 3`; pxx reports 2.7 and has
  weak symbols, so the patch drops the version test. The server's own
  definitions then win in Xfbdev, as with gcc, with no objcopy.
- **xedit** loads its Lisp from `/usr/lib/X11/xedit/lisp` at start-up; the
  bundle ships it. Without it, xedit's error path longjmps through a buffer
  not yet set (a SIGSEGV in the gcc build too).
- **LVGL demo:** `bin/lvgl-demo` draws straight into `/dev/fb0`, no X. Set
  `LV_EVDEV=/dev/input/eventN` for a pointer and `LV_FBDEV` for another
  framebuffer. In QEMU it is pixel-identical to a gcc build.
- **Checked in QEMU on /dev/fb0:** the all-pxx stack is pixel-identical to
  the same clients on a gcc-built Xfbdev. Keyboard and mouse work.
