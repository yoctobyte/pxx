#!/bin/sh
# Path B, host side: the bundle's core X fonts, into $PATHB_WORK/recipe/fonts/misc
# (record.py and make_bundle.sh take them from there). bdftopcf, ucs2any and
# mkfontdir are host tools, so the fonts travel in the recipe as data,
# converted from public-domain BDFs (font-misc-misc, font-cursor-misc; their
# COPYING goes in the bundle).
#   the cursor font; misc-fixed 6x13 in ISO10646-1; and 6x10, 6x13, 7x13,
#   8x13, 9x15 with their bold variants in ISO8859-1. The Athena widgets'
#   default font and fontset ask for ISO8859-*, xcalc asks for 8x13. The
#   ISO8859-1 encodings are made as font-misc-misc's own build makes them,
#   with ucs2any and font-util's map.
set -eu
B=${PATHB_WORK:?set PATHB_WORK}
MD=$B/recipe/fonts/misc
X=$B/fonts.tmp
mkdir -p $MD $X
tar -xJf $B/dl/font-misc-misc-1.1.3.tar.xz -C $X
tar -xJf $B/dl/font-cursor-misc-1.0.4.tar.xz -C $X
MAP=${PATHB_ISO8859_1_MAP:-/usr/share/fonts/X11/util/map-ISO8859-1}
[ -f $MAP ] || { echo "fonts.sh: no $MAP (font-util / xfonts-utils; or set PATHB_ISO8859_1_MAP)"; exit 1; }
bdftopcf -t $X/font-misc-misc-1.1.3/6x13.bdf | gzip -9n > $MD/6x13.pcf.gz
bdftopcf -t $X/font-cursor-misc-1.0.4/cursor.bdf | gzip -9n > $MD/cursor.pcf.gz
for f in 6x10 6x13 6x13B 7x13 7x13B 8x13 8x13B 9x15 9x15B; do
  ( cd $X && ucs2any font-misc-misc-1.1.3/$f.bdf $MAP ISO8859-1 > /dev/null )
  bdftopcf -t $X/$f-ISO8859-1.bdf | gzip -9n > $MD/$f-ISO8859-1.pcf.gz
done
mkfontdir $MD
# the short names (font-alias's misc set, for the fonts shipped): `8x13',
# `8x13bold', ..., `fixed' and `variable' (no Helvetica here, so a bold fixed)
{
  for f in 6x10 6x13 7x13 8x13 9x15; do
    echo "$f $(grep "^$f-ISO8859-1.pcf.gz " $MD/fonts.dir | cut -d' ' -f2-)"
    echo "${f}bold $(grep "^${f}B-ISO8859-1.pcf.gz " $MD/fonts.dir | cut -d' ' -f2-)"
  done | grep -v ' $'
  echo "fixed $(grep '^6x13-ISO8859-1.pcf.gz ' $MD/fonts.dir | cut -d' ' -f2-)"
  echo "variable $(grep '^6x13B-ISO8859-1.pcf.gz ' $MD/fonts.dir | cut -d' ' -f2-)"
} > $MD/fonts.alias
echo "fonts done"
