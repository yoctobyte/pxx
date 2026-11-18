#!/bin/sh
# Assemble pixx's Path B desktop bundle from $PATHB_WORK/bin and the pinned
# font sources: a root-relative tree, a tarball, and its sha256.
#   out: $PATHB_WORK/bundle/pixx-pathb-desktop-x86_64.tar.gz
set -e
T=$(cd "$(dirname "$0")" && pwd)
B=${PATHB_WORK:?set PATHB_WORK}
O=$B/bundle
R=$O/root
mkdir -p $R/usr/bin $R/etc/fonts $R/usr/share/fonts/X11/misc \
         $R/usr/share/fonts/truetype/dejavu $R/usr/share/licenses/pathb
cp $B/bin/Xfbdev $B/bin/dwm $B/bin/st $R/usr/bin/
# LVGL's widgets demo, no X: straight on /dev/fb0 (lvgl.sh)
[ -x $B/bin/lvgl-demo ] && cp $B/bin/lvgl-demo $R/usr/bin/lvgl-demo
install -m 755 $T/files/startx-pixx $R/usr/bin/startx-pixx
cp $T/files/fonts.conf $R/etc/fonts/fonts.conf
X=$(mktemp -d)
# the server's core fonts: `fixed' (misc-fixed 6x13, public domain) and the
# cursor font, from their X.org sources
tar -xJf $B/dl/font-misc-misc-1.1.3.tar.xz -C $X
tar -xJf $B/dl/font-cursor-misc-1.0.4.tar.xz -C $X
bdftopcf -t $X/font-misc-misc-1.1.3/6x13.bdf | gzip -9n > $R/usr/share/fonts/X11/misc/6x13.pcf.gz
bdftopcf -t $X/font-cursor-misc-1.0.4/cursor.bdf | gzip -9n > $R/usr/share/fonts/X11/misc/cursor.pcf.gz
mkfontdir $R/usr/share/fonts/X11/misc
echo 'fixed -misc-fixed-medium-r-semicondensed--13-120-75-75-c-60-iso10646-1' > $R/usr/share/fonts/X11/misc/fonts.alias
tar -xjf $B/dl/dejavu-fonts-ttf-2.37.tar.bz2 -C $X
for f in DejaVuSans DejaVuSans-Bold DejaVuSansMono DejaVuSansMono-Bold DejaVuSansMono-Oblique DejaVuSansMono-BoldOblique; do
  cp $X/dejavu-fonts-ttf-2.37/ttf/$f.ttf $R/usr/share/fonts/truetype/dejavu/
done
# licences
L=$R/usr/share/licenses/pathb
cp $X/dejavu-fonts-ttf-2.37/LICENSE $L/dejavu-fonts.LICENSE
cp $X/font-misc-misc-1.1.3/COPYING $L/font-misc-misc.COPYING
cp $X/font-cursor-misc-1.0.4/COPYING $L/font-cursor-misc.COPYING
cp $B/src/tinyx/COPYING $L/tinyx.COPYING
for p in libXau xtrans libxcb libX11 libXext libXrender expat fontconfig libXft zlib libfontenc libXfont; do
  for f in COPYING LICENSE; do [ -f $B/src/$p/$f ] && cp $B/src/$p/$f $L/$p.$f; done
done
cp $B/src/freetype/docs/FTL.TXT $L/freetype.FTL.TXT
cp $B/src/st-0.9.2/LICENSE $L/st.LICENSE
cp $B/src/dwm-6.5/LICENSE $L/dwm.LICENSE
[ -f $B/src/lvgl/LICENCE.txt ] && cp $B/src/lvgl/LICENCE.txt $L/lvgl.LICENCE.txt
cp $T/files/README.bundle $L/README
cp $T/patches/*.patch $L/
# a reproducible tarball: fixed owner, order and mtime
tar -C $R --sort=name --owner=0 --group=0 --numeric-owner --mtime=2026-01-01 -cf - . | gzip -9n > $O/pixx-pathb-desktop-x86_64.tar.gz
( cd $O && sha256sum pixx-pathb-desktop-x86_64.tar.gz > pixx-pathb-desktop-x86_64.tar.gz.sha256 )
cat $O/pixx-pathb-desktop-x86_64.tar.gz.sha256
