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
mv $OUT.tmp $OUT
echo "linkplan: $(grep -c . $OUT) programs -> $OUT"
