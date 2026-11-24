#!/bin/sh
# Assemble pixx's Path B desktop bundle: a root-relative tree, a tarball, its
# sha256, and bundle.manifest. POSIX sh and toybox-level tools only: it runs
# on site (onsite.sh's last stage) as well as on the host.
# Env: W (work dir), RECIPE (default $W/recipe), DL (default $W/dl).
# In:  $W/bin (the programs), $W/stage (headers and data, from gen.tar),
#      $W/src (licences), $RECIPE/tools/files, $RECIPE/fonts, $DL (DejaVu,
#      xbitmaps).
# Out: $W/bundle/pixx-pathb-desktop-x86_64.tar.gz (+ .sha256) and
#      $W/bundle/bundle.manifest: "sha256 mode path" for every file (and
#      "-> target" for a link), sorted. The manifest is the check that two
#      builds made the same bundle; the tarball's own bytes depend on the
#      tar and gzip that wrote it.
set -eu
W=${W:?set W to the work dir}
RECIPE=${RECIPE:-$W/recipe}
DL=${DL:-$W/dl}
F=$RECIPE/tools/files
O=$W/bundle
R=$O/root
X=$W/build/bundle.tmp.$$
# a tree left by an earlier run would add its stale files: move it aside
if [ -e $R ]; then mv $R $W/build/bundle-root.old.$$; fi
mkdir -p $R/usr/bin $R/etc/fonts $R/usr/share/fonts/X11/misc \
         $R/usr/share/fonts/truetype/dejavu $R/usr/share/licenses/pathb $X
for p in Xfbdev dwm st jwm xclock xcalc xeyes xload xedit; do cp $W/bin/$p $R/usr/bin/; done
mkdir -p $R/etc/jwm $R/usr/share/pixix $R/usr/share/X11/app-defaults $R/usr/share/X11/locale
cp $F/system.jwmrc $R/etc/jwm/system.jwmrc
cp $F/welcome.txt $R/usr/share/pixix/welcome.txt
# the Athena apps' resources (libXt searches /usr/share/X11/app-defaults)
cp $W/stage/usr/share/X11/app-defaults/* $R/usr/share/X11/app-defaults/
# xedit's Lisp files, where its compiled-in /usr/lib/X11/xedit/lisp points
mkdir -p $R/usr/lib/X11/xedit
cp -R $W/stage/usr/lib/X11/xedit/lisp $R/usr/lib/X11/xedit/
# Xlib's locale data, for XSupportsLocale and the Xmb/Xutf8 conversions:
# the C and en_US.UTF-8 locales and the tables that map names to them
XL=$W/stage/usr/share/X11/locale
cp $XL/locale.alias $XL/locale.dir $XL/compose.dir $R/usr/share/X11/locale/
for l in C en_US.UTF-8 iso8859-1; do cp -R $XL/$l $R/usr/share/X11/locale/; done
# LVGL's widgets demo, no X: straight on /dev/fb0
if [ -x $W/bin/lvgl-demo ]; then cp $W/bin/lvgl-demo $R/usr/bin/lvgl-demo; fi
cp $F/startx-pixx $R/usr/bin/startx-pixx
cp $F/fonts.conf $R/etc/fonts/fonts.conf
# the server's core fonts (fonts.sh made them on the recording host)
cp $RECIPE/fonts/misc/* $R/usr/share/fonts/X11/misc/
# the standard X bitmaps (xcalc's and xedit's icons), where libXmu's
# compiled-in /usr/include/X11/bitmaps points
xzcat $DL/xbitmaps-1.1.3.tar.xz | tar -xf - -C $X
mkdir -p $R/usr/include/X11/bitmaps
for f in $X/xbitmaps-1.1.3/*; do
  case ${f##*/} in
    COPYING|ChangeLog|README*|INSTALL|Makefile*|configure*|aclocal.m4|*.pc*|missing|install-sh|compile|depcomp|config.*|m4|autom4te.cache) ;;
    *) if [ -f $f ]; then cp $f $R/usr/include/X11/bitmaps/; fi ;;
  esac
done
bzcat $DL/dejavu-fonts-ttf-2.37.tar.bz2 | tar -xf - -C $X
for f in DejaVuSans DejaVuSans-Bold DejaVuSansMono DejaVuSansMono-Bold DejaVuSansMono-Oblique DejaVuSansMono-BoldOblique; do
  cp $X/dejavu-fonts-ttf-2.37/ttf/$f.ttf $R/usr/share/fonts/truetype/dejavu/
done
xzcat $DL/font-misc-misc-1.1.3.tar.xz | tar -xf - -C $X
xzcat $DL/font-cursor-misc-1.0.4.tar.xz | tar -xf - -C $X
# licences
L=$R/usr/share/licenses/pathb
cp $X/dejavu-fonts-ttf-2.37/LICENSE $L/dejavu-fonts.LICENSE
cp $X/font-misc-misc-1.1.3/COPYING $L/font-misc-misc.COPYING
cp $X/font-cursor-misc-1.0.4/COPYING $L/font-cursor-misc.COPYING
cp $X/xbitmaps-1.1.3/COPYING $L/xbitmaps.COPYING
cp $W/src/tinyx/COPYING $L/tinyx.COPYING
for p in libXau xtrans libxcb libX11 libXext libXrender expat fontconfig libXft zlib libfontenc libXfont; do
  for f in COPYING LICENSE; do if [ -f $W/src/$p/$f ]; then cp $W/src/$p/$f $L/$p.$f; fi; done
done
cp $W/src/freetype/docs/FTL.TXT $L/freetype.FTL.TXT
cp $W/src/st-0.9.2/LICENSE $L/st.LICENSE
cp $W/src/dwm-6.5/LICENSE $L/dwm.LICENSE
cp $W/src/jwm/LICENSE $L/jwm.LICENSE
for p in libICE libSM libXt libXmu libXpm libXaw xclock xcalc xeyes xload xedit; do
  cp $W/src/$p/COPYING $L/$p.COPYING
done
if [ -f $W/src/lvgl/LICENCE.txt ]; then cp $W/src/lvgl/LICENCE.txt $L/lvgl.LICENCE.txt; fi
cp $F/README.bundle $L/README
cp $RECIPE/tools/patches/*.patch $L/
# file modes do not depend on the umask or the tools that copied them
find $R -type d -exec chmod 755 {} +
find $R -type f -exec chmod 644 {} +
for p in $R/usr/bin/*; do chmod 755 $p; done
# the manifest: the check that two builds agree
( cd $R && LC_ALL=C find . \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then printf 'link %s %s -> %s\n' "$(stat -c %a "$f")" "$f" "$(readlink "$f")"
    else printf '%s %s %s\n' "$(sha256sum < "$f" | cut -d' ' -f1)" "$(stat -c %a "$f")" "$f"; fi
  done ) > $O/bundle.manifest
# the tarball: reproducible with GNU tar; plain otherwise (the manifest is the check)
TB=$O/pixx-pathb-desktop-x86_64.tar.gz
if tar --version 2>/dev/null | grep -q 'GNU tar'; then
  tar -C $R --sort=name --owner=0 --group=0 --numeric-owner --mtime=2026-01-01 -cf - . | gzip -9n > $TB
else
  ( cd $R && tar -cf - . ) | gzip -9 > $TB
fi
( cd $O && sha256sum pixx-pathb-desktop-x86_64.tar.gz > pixx-pathb-desktop-x86_64.tar.gz.sha256 )
echo "bundle: $(grep -c . $O/bundle.manifest) files, manifest sha256 $(sha256sum < $O/bundle.manifest | cut -d' ' -f1)"
cat $O/pixx-pathb-desktop-x86_64.tar.gz.sha256
