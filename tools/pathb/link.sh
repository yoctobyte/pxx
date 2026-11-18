#!/bin/sh
# Build the three Path B programs with pxx from the replay objects:
#   st 0.9.2 and dwm 6.5: their own .c files --emit-obj, then --link with the
#   pxx-compiled X client libraries;
#   Xfbdev: every TinyX object on gcc's Xfbdev link line, plus the pxx-compiled
#   libXfont/freetype/fontenc/zlib members that ld would have pulled.
# Out: $PATHB_WORK/bin/{st,dwm,Xfbdev}. Also gcc builds of st and dwm
# ($PATHB_WORK/bin/{st,dwm}_gcc) as the comparison reference.
set -e
T=$(cd "$(dirname "$0")" && pwd)
B=${PATHB_WORK:?set PATHB_WORK}
PXX=${PXXC:-$T/../../compiler/pascal26}
FL=${PXXFLAGS:---shared-runtime --threadsafe}
INC="-I$B/prefix/include -I$B/prefix/include/freetype2"
mkdir -p $B/bin $B/obj/st $B/obj/dwm $B/obj/loc
GLIBS="$B/prefix/lib/libXft.a $B/prefix/lib/libXrender.a $B/prefix/lib/libfontconfig.a \
 $B/prefix/lib/libfreetype.a $B/prefix/lib/libexpat.a $B/prefix/lib/libX11.a \
 $B/prefix/lib/libxcb.a $B/prefix/lib/libXau.a -lm -lpthread"
XOBJS=$(python3 $T/libobjs.py libXft:libXft libXrender:libXrender fontconfig:libfontconfig \
       freetype:libfreetype expat:libexpat libX11:libX11 libxcb:libxcb libXau:libXau 2>/dev/null)

# st 0.9.2: st.c x.c with the default config.def.h; openpty (-lutil) and
# clock_gettime (-lrt) come from libc / crtl
cd $B/src/st-0.9.2
[ -f config.h ] || cp config.def.h config.h
SDEF='-DVERSION="0.9.2" -D_XOPEN_SOURCE=600'
gcc -O2 -w $SDEF $INC st.c x.c $GLIBS -lutil -lrt -o $B/bin/st_gcc
for f in st x; do $PXX --emit-obj $FL $SDEF $INC $f.c $B/obj/st/$f.o >/dev/null; done
$PXX --link -o $B/bin/st $B/obj/st/st.o $B/obj/st/x.o $XOBJS >/dev/null

# dwm 6.5 without Xinerama, default config.def.h
cd $B/src/dwm-6.5
[ -f config.h ] || cp config.def.h config.h
DDEF='-DVERSION="6.5" -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L'
gcc -O2 -w -std=c99 $DDEF $INC drw.c dwm.c util.c $GLIBS -o $B/bin/dwm_gcc
for f in drw dwm util; do $PXX --emit-obj $FL $DDEF $INC $f.c $B/obj/dwm/$f.o >/dev/null; done
$PXX --link -o $B/bin/dwm $B/obj/dwm/drw.o $B/obj/dwm/dwm.o $B/obj/dwm/util.o $XOBJS >/dev/null

# Xfbdev. libXfont's stubs and util/miscutil.c define fallbacks for server
# symbols `weak' only when __GNUC__ >= 3, and pxx reports 2.7, so they come
# out strong: drop_dups.py pulls library members with ld's archive rule and
# makes a pulled member's duplicates local, which is what gcc's weak gives.
OBJS=$(python3 $T/xfb_objs.py)
LIBS=$(python3 $T/libobjs.py libXfont:libXfont freetype:libfreetype libfontenc:libfontenc zlib:libz 2>/dev/null)
LIBS=$(python3 $T/drop_dups.py $B/obj/loc "$OBJS" "$LIBS" 2>/dev/null)
$PXX --link -o $B/bin/Xfbdev $OBJS $LIBS >/dev/null
ls -la $B/bin/st $B/bin/dwm $B/bin/Xfbdev
