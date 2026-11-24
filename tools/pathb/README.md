# Path B: an X11 desktop compiled by pxx

This builds pixx's own desktop: the TinyX Xfbdev framebuffer X server, the
JWM window manager (dwm with `PIXX_WM=dwm`), the st terminal, xclock, xcalc,
xeyes, xload, xedit and LVGL's framebuffer demo. Every C file, the X
libraries included (Xlib, xcb, Xt, Xaw, Xmu, Xpm, Xft, fontconfig, freetype,
expat, libXfont, zlib), is compiled and linked by pxx. The binaries are static
and use pxx's crtl, not glibc.

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
   - `drop_dups.py` pulls library members by ld's archive rule.
   It stops if a member would need `objcopy --localize-symbol`, since the
   target has none.
8. `onsite.sh WORK link bundle`: the target's last two stages.

## The on-site side

`onsite.sh WORKDIR [unpack|compile|link|bundle]...` (all four by default):
unpack the tarballs and lay `gen.tar.gz` over them, run `compile.list` with
`JOBS` jobs, run `link.list`, then `make_bundle.sh`. Tools: sh, tar, xzcat,
bzcat, zcat, gzip, sed, sort, grep, cut, find, stat, sha256sum, readlink,
cp, mv, chmod, mkdir, and pxx (with `PXX_HOME`). No gcc, make, autoconf,
python, patch, ar, nm or objcopy. Tested under busybox with nothing else on
`PATH`.

The recipe is tied to the pxx commit in `RECIPE`: `link.list` was computed
from that pxx's objects. A different pxx needs a new recording.

## Tests

`qemu-test.sh KERNEL out.png` boots a Linux kernel (fbdev and devtmpfs
required) with busybox and the bundle. Its `/init` runs `startx-pixx`; the
script then types, moves the pointer and takes a screendump.

## Host requirements

gcc, autoconf/automake/libtool, make, python3, patch, curl, binutils (nm,
ar), bdftopcf, mkfontdir, ucs2any with font-util's `map-ISO8859-1`, and a
pxx compiler. For the test, also qemu-system-x86_64, a static busybox and
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
