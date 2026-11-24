#!/bin/bash
# Path B reference build with gcc: the X11 client stack, the TinyX Xfbdev
# server, JWM and the Athena apps, static. One verbose -j1 make log per
# package in $PATHB_WORK/logs: record.py turns exactly those compiles
# into the on-site recipe of pxx compiles. Each package
# is extracted fresh into $PATHB_WORK/src.
#
# Configured for the TARGET's layout (--prefix=/usr, /etc, /var) and
# installed into the staging root $PATHB_WORK/stage with DESTDIR, the usual
# cross-compile arrangement: every path compiled into a program (Xlib's
# XKeysymDB and locale dir, fontconfig's /etc/fonts, Xt's app-defaults,
# xedit's Lisp, Xmu's bitmaps, Xfbdev's font path) is then where the bundle
# puts the files on the target, never this work dir. Later packages find
# earlier ones through pkg-config's sysroot.
set -u
T=$(cd "$(dirname "$0")" && pwd)
B=${PATHB_WORK:?set PATHB_WORK}
S=$B/stage          # DESTDIR
U=$S/usr            # what the target calls /usr
mkdir -p $B/src $B/logs $U
# LIBDIR, not PATH: no host .pc files (libxcb found the host libXdmcp)
export PKG_CONFIG_LIBDIR=$U/lib/pkgconfig:$U/share/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=$S
export ACLOCAL_PATH=$U/share/aclocal
# Static libraries: pkg-config hands configure the private libraries too.
# The .la files that used to carry them are gone (stage_install), so without
# this Xfbdev's link loses libXfont's freetype and the apps Xft's fontconfig.
export PKG_CONFIG="pkg-config --static"
CFG="--prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-shared --enable-static"
done_or() { [ -f $B/logs/$1.done ] && { echo "skip $1"; return 0; }; return 1; }
ok()   { touch $B/logs/$1.done; echo "ok   $1"; }
fail() { echo "FAIL $1 (see $B/logs/$1.*.log)"; return 1; }
# extract fresh, then apply tools/pathb/patches/NAME-*.patch (the recipe
# records the patched files, so on site needs no patch tool)
src()  {  # name tarball
  d=$B/src/$1
  [ -d $d ] && return 0
  mkdir -p $d && tar -xf $B/dl/$2 -C $d --strip-components=1 || return 1
  for p in $T/patches/$1-*.patch; do
    [ -f $p ] || continue
    patch -p1 -d $d < $p > /dev/null || { echo "patch $p failed"; return 1; }
  done
}
# a package not marked done starts from a fresh tree: a rerun in an old one
# would compile nothing and leave a make log without the compiles that
# record.py turns into the recipe
fresh() {  # name
  if [ -e $B/src/$1 ]; then mkdir -p $B/old; mv $B/src/$1 $B/old/$1.$$; fi
}
# libtool archives name /usr/lib, which would be the HOST's: static
# libraries link by -L/-l from pkg-config without them
stage_install() {  # name
  make install DESTDIR=$S > $B/logs/$1.install.log 2>&1 \
    && find $S -name '*.la' -exec rm -f {} +
}
pkg() {   # name tarball [configure args...]
  n=$1; t=$2; shift 2
  done_or $n && return 0
  fresh $n
  src $n $t || { fail $n; return 1; }
  ( cd $B/src/$n && ./configure $CFG "$@" > $B/logs/$n.configure.log 2>&1 \
      && make -w V=1 -j1 > $B/logs/$n.make.log 2>&1 \
      && stage_install $n ) && ok $n || fail $n
}
pkg xorgproto  xorgproto-2024.1.tar.xz        || exit 1
pkg libXau     libXau-1.0.12.tar.xz           || exit 1
pkg xtrans     xtrans-1.5.2.tar.xz            || exit 1
pkg xcb-proto  xcb-proto-1.17.0.tar.xz        || exit 1
pkg libxcb     libxcb-1.17.0.tar.xz --disable-devel-docs --without-doxygen || exit 1
pkg libX11     libX11-1.8.10.tar.xz --disable-specs --disable-xf86bigfont || exit 1
pkg libXext    libXext-1.3.6.tar.xz --disable-specs || exit 1
pkg libXrender libXrender-0.9.12.tar.xz       || exit 1
pkg expat      expat-2.6.4.tar.xz --without-docbook --without-examples --without-tests || exit 1
pkg freetype   freetype-2.13.3.tar.xz --without-zlib --without-bzip2 --without-png --without-harfbuzz --without-brotli || exit 1
pkg fontconfig fontconfig-2.15.0.tar.xz --disable-docs --disable-nls --disable-cache-build || exit 1
pkg libXft     libXft-2.3.8.tar.xz            || exit 1

# --- the X server (TinyX Xfbdev) and what it needs ---
# zlib's configure is not autoconf: no --disable-shared
if ! done_or zlib; then
  fresh zlib
  src zlib zlib-1.3.1.tar.gz
  ( cd $B/src/zlib && ./configure --prefix=/usr --static > $B/logs/zlib.configure.log 2>&1 \
      && make -w V=1 -j1 > $B/logs/zlib.make.log 2>&1 && stage_install zlib ) \
    && ok zlib || { fail zlib; exit 1; }
fi
pkg libfontenc libfontenc-1.1.8.tar.xz            || exit 1
pkg libXfont   libXfont-1.5.4.tar.bz2 --disable-devel-docs --without-xmlto --without-fop || exit 1
# TinyX is a git snapshot: patch, autoreconf, then configure. Its old C needs
# gcc's permissive flags (implicit int and friends are errors in gcc 14+).
# Its default font path is the bundle's misc dir (startx-pixx passes -fp too).
if ! done_or tinyx; then
  fresh tinyx
  src tinyx tinyx-feab72c.tar.gz || exit 1
  ( cd $B/src/tinyx && autoreconf -fi > $B/logs/tinyx.autoreconf.log 2>&1 \
      && ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
           --with-fontdir=/usr/share/fonts/X11 --with-default-font-path=/usr/share/fonts/X11/misc/ \
           CFLAGS="-O2 -std=gnu99 -Wno-error=implicit-int -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=return-mismatch" > $B/logs/tinyx.configure.log 2>&1 \
      && make -w V=1 -j1 > $B/logs/tinyx.make.log 2>&1 && stage_install tinyx ) \
    && ok tinyx || { fail tinyx; exit 1; }
fi
for n in st-0.9.2 dwm-6.5; do src $n $n.tar.gz; done

# --- JWM and the Athena-widget apps for its menu ---
pkg libICE     libICE-1.1.1.tar.xz --disable-docs --disable-specs --without-xmlto --without-fop || exit 1
pkg libSM      libSM-1.2.4.tar.xz --disable-docs --without-libuuid --without-xmlto --without-fop || exit 1
# Xt's resource search path: app-defaults in /usr/share/X11 (the default from
# --prefix=/usr would also try /usr/lib/X11; this is the bundle's one place)
pkg libXt      libXt-1.3.1.tar.xz --disable-specs --without-xmlto --without-fop \
  --with-xfile-search-path='/usr/share/X11/%L/%T/%N%C%S:/usr/share/X11/%T/%N%C%S:/usr/share/X11/%L/%T/%N%S:/usr/share/X11/%T/%N%S' || exit 1
# Xmu finds bitmaps (the apps' icons) in /usr/include/X11/bitmaps, where the
# bundle puts xbitmaps
pkg libXmu     libXmu-1.2.1.tar.xz --disable-docs --without-xmlto --without-fop || exit 1
pkg libXpm     libXpm-3.5.17.tar.xz --disable-open-zfile --disable-stat-zfile || exit 1
pkg libXaw     libXaw-1.0.16.tar.xz --disable-xaw6 --disable-specs --without-xmlto --without-fop || exit 1
# The apps. xedit's Lisp loads its .lsp files from /usr/lib/X11/xedit/lisp at
# start-up; without them its error path longjmps through a buffer not yet
# set (a SIGSEGV in the gcc build too), so make_bundle.sh ships them.
# Their configure takes app-defaults' dir from xt.pc, where pkg-config has
# put the sysroot in front: name the target's dir instead.
AD=--with-appdefaultdir=/usr/share/X11/app-defaults
pkg xclock     xclock-1.1.1.tar.xz $AD --without-xkb || exit 1
pkg xcalc      xcalc-1.1.2.tar.xz  $AD               || exit 1
pkg xeyes      xeyes-1.1.2.tar.bz2                   || exit 1
pkg xload      xload-1.2.0.tar.xz  $AD --disable-nls || exit 1
pkg xedit      xedit-1.2.4.tar.xz  $AD               || exit 1
# JWM looks for its libraries with AC_CHECK_LIB, not pkg-config, so a static
# link test needs the whole chain in LIBS. Its Makefile then links with
# `$(OBJECTS) $(LDFLAGS)` and never reads LIBS, so the chain goes into LDFLAGS
# too (configure's own tests put LDFLAGS before the test object, where the
# libraries resolve nothing, so it is harmless there). No PNG/JPEG/cairo/
# rsvg/pango/Xinerama; Xft, Xrender, XPM icons, SHAPE and Xmu are on. Its
# system config is /etc/jwm/system.jwmrc, the bundle's.
JWMLIBS="-lXft -lXrender -lfontconfig -lfreetype -lexpat -lXpm -lXmu -lXt -lSM -lICE -lXext -lX11 -lxcb -lXau -lm -lpthread"
pkg jwm        jwm-2.4.6.tar.xz --sysconfdir=/etc/jwm --disable-png --disable-cairo --disable-rsvg --disable-jpeg \
  --disable-pango --disable-xinerama --disable-nls --enable-xft --enable-xrender --enable-xpm \
  --enable-shape --enable-xmu CPPFLAGS="-I$U/include -I$U/include/freetype2" LDFLAGS="-L$U/lib $JWMLIBS" \
  LIBS="$JWMLIBS" || exit 1
echo "gcc reference build done"
