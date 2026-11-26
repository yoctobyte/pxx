#!/bin/sh
# Path B, host side, after onsite.sh's compile stage: decide what every
# program links, and write it to $PATHB_WORK/recipe/link.list (OUT TAB OBJ...,
# @W@ for the work dir). onsite.sh's link stage runs it, here and on site, so
# the target needs no ar, nm, objcopy or python.
#   st 0.9.2, dwm 6.5: their objects plus every member of the X client libraries
#   Xfbdev: every TinyX object on gcc's Xfbdev link line, plus the
#     libXfont/freetype/fontenc/zlib members ld would have pulled
#   jwm and the Athena apps: each program's objects off its gcc link line,
#     plus the library members ld's archive rule pulls, in ld's order
#     (libXaw's Vendor.o replaces libXt's)
#   lvgl-demo: every LVGL object
# A pulled member that defines a symbol the program already defines would
# need objcopy --localize-symbol on site; there is none, so that stops here.
# (libXfont's serverGeneration/serverClient were the two; patches/
# libXfont-weak-stubs.patch makes them weak, as they are with gcc.)
set -eu
T=$(cd "$(dirname "$0")" && pwd)
B=${PATHB_WORK:?set PATHB_WORK}
B=$(cd "$B" && pwd -P)
export PATHB_WORK=$B
mkdir -p $B/build/dd
TAB=$(printf '\t')
OUT=$B/recipe/link.list
: > $OUT.tmp
emit() {  # OUT OBJ...
  { printf '%s' "$1"; shift; for o in "$@"; do printf '\t%s' "$o"; done; printf '\n'; } \
    | sed "s|$B/|@W@/|g" >> $OUT.tmp
}
pulled() {  # OUTDIR 'BASE' 'LIB' [first] -> the LIB objects to link
  python3 $T/drop_dups.py "$@" 2> $B/build/dd/err
  if grep -q '^localized in' $B/build/dd/err; then
    echo "linkplan: a pulled member needs a local copy (no objcopy on site):" >&2
    grep '^localized in' $B/build/dd/err >&2
    exit 1
  fi
}
XOBJS=$(python3 $T/libobjs.py libXft:libXft libXrender:libXrender fontconfig:libfontconfig \
       freetype:libfreetype expat:libexpat libX11:libX11 libxcb:libxcb libXau:libXau 2>/dev/null)
# shellcheck disable=SC2086
emit $B/bin/st $B/obj/st/st.o $B/obj/st/x.o $XOBJS
# shellcheck disable=SC2086
emit $B/bin/dwm $B/obj/dwm/drw.o $B/obj/dwm/dwm.o $B/obj/dwm/util.o $XOBJS
OBJS=$(python3 $T/xfb_objs.py)
LIBS=$(python3 $T/libobjs.py libXfont:libXfont freetype:libfreetype libfontenc:libfontenc zlib:libz 2>/dev/null)
LIBS=$(pulled $B/build/dd/xfb "$OBJS" "$LIBS")
# shellcheck disable=SC2086
emit $B/bin/Xfbdev $OBJS $LIBS
TLIBS=$(python3 $T/libobjs.py libXaw:libXaw7 libXpm:libXpm libXmu:libXmu libXt:libXt \
        libSM:libSM libICE:libICE libXext:libXext 2>/dev/null)
for p in jwm xclock xcalc xeyes xload xedit; do
  P=$(python3 $T/prog_objs.py $p $p)
  L=$(pulled $B/build/dd/$p "$P" "$TLIBS $XOBJS" first)
  # shellcheck disable=SC2086
  emit $B/bin/$p $P $L
done
# shellcheck disable=SC2086
emit $B/bin/lvgl-demo $(ls $B/obj/lvgl/o/*.o | LC_ALL=C sort)
# Xorg: every member of the server archives on gcc's Xorg link line (run in
# hw/xfree86), sdksyms.o, the modules it would dlopen (modesetting, shadow,
# evdev) and their table, plus the library members ld would pull. libxcvt is
# one file, and its meson file builds it shared only: its object directly.
if [ -f $B/logs/xorg-server.done ]; then
  XA="../../dix/.libs/libmain.a ../../dix/.libs/libdix.a loader/.libs/libloader.a
    common/.libs/libcommon.a os-support/.libs/libxorgos.a parser/.libs/libxf86config.a
    dixmods/.libs/libdixmods.a modes/.libs/libxf86modes.a ramdac/.libs/libramdac.a
    ddc/.libs/libddc.a i2c/.libs/libi2c.a ../../composite/.libs/libcomposite.a
    ../../xfixes/.libs/libxfixes.a ../../Xext/.libs/libXext.a ../../dbe/.libs/libdbe.a
    ../../record/.libs/librecord.a ../../randr/.libs/librandr.a ../../render/.libs/librender.a
    ../../damageext/.libs/libdamageext.a ../../present/.libs/libpresent.a
    ../../miext/damage/.libs/libdamage.a ../../Xi/.libs/libXi.a ../../xkb/.libs/libxkb.a
    xkb/.libs/libxorgxkb.a dri2/.libs/libdri2.a ../../fb/.libs/libfb.a
    ../../miext/sync/.libs/libsync.a ../../mi/.libs/libmi.a ../../os/.libs/libos.a
    ../../Xext/.libs/libXvidmode.a dixmods/.libs/libshadow.a
    drivers/modesetting/.libs/modesetting_drv.a"
  # shellcheck disable=SC2086
  OBJS="$B/replay/xorg-server/hw_xfree86_sdksyms.c.o $(python3 $T/arc_objs.py xorg-server hw/xfree86 $XA)
    $(python3 $T/arc_objs.py xf86-input-evdev src .libs/evdev_drv.a) $B/obj/xorg/static-modules.o
    $B/replay/libxcvt/lib_libxcvt.c.o"
  LIBS=$(python3 $T/libobjs.py libmd:libmd pixman:libpixman-1 libXfont2:libXfont2 libfontenc:libfontenc \
         freetype:libfreetype zlib:libz libXau:libXau libdrm:libdrm libevdev:libevdev mtdev:libmtdev 2>/dev/null)
  LIBS=$(pulled $B/build/dd/xorg "$OBJS" "$LIBS")
  # shellcheck disable=SC2086
  emit $B/bin/Xorg $OBJS $LIBS
  # xkbcomp: the server runs it to compile the keymap
  P=$(python3 $T/prog_objs.py xkbcomp xkbcomp)
  XK=$(python3 $T/libobjs.py libxkbfile:libxkbfile libX11:libX11 libxcb:libxcb libXau:libXau 2>/dev/null)
  L=$(pulled $B/build/dd/xkbcomp "$P" "$XK" first)
  # shellcheck disable=SC2086
  emit $B/bin/xkbcomp $P $L
fi
mv $OUT.tmp $OUT
echo "linkplan: $(grep -c . $OUT) programs -> $OUT"
