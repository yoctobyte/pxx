#!/bin/bash
# Path B reference build with gcc: the X11 client stack and the TinyX Xfbdev
# server, static, into $PATHB_WORK/prefix. One verbose -j1 make log per
# package in $PATHB_WORK/logs: replay-cc.py replays exactly those compiles
# through pxx. Each package is extracted fresh into $PATHB_WORK/src.
set -u
T=$(cd "$(dirname "$0")" && pwd)
B=${PATHB_WORK:?set PATHB_WORK}
P=$B/prefix
mkdir -p $B/src $B/logs $P
# LIBDIR, not PATH: no host .pc files (libxcb found the host libXdmcp)
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig:$P/share/pkgconfig
export PATH=$P/bin:$PATH
export ACLOCAL_PATH=$P/share/aclocal
CFG="--prefix=$P --disable-shared --enable-static"
done_or() { [ -f $B/logs/$1.done ] && { echo "skip $1"; return 0; }; return 1; }
ok()   { touch $B/logs/$1.done; echo "ok   $1"; }
fail() { echo "FAIL $1 (see $B/logs/$1.*.log)"; return 1; }
src()  {  # name tarball
  d=$B/src/$1; [ -d $d ] || { mkdir -p $d && tar -xf $B/dl/$2 -C $d --strip-components=1; }
}
# MK="VAR=value" before pkg: a make variable for the COMPILE step only. A
# path compiled into the code can then be the target's (/usr/...) while
# `make install` still installs under $P, which make_bundle.sh copies from.
pkg() {   # name tarball [configure args...]
  n=$1; t=$2; shift 2
  done_or $n && return 0
  src $n $t
  ( cd $B/src/$n && ./configure $CFG "$@" > $B/logs/$n.configure.log 2>&1 \
      && make -w V=1 -j1 ${MK:+"$MK"} > $B/logs/$n.make.log 2>&1 \
      && make install > $B/logs/$n.install.log 2>&1 ) && ok $n || fail $n
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
  src zlib zlib-1.3.1.tar.gz
  ( cd $B/src/zlib && ./configure --prefix=$P --static > $B/logs/zlib.configure.log 2>&1 \
      && make -w V=1 -j1 > $B/logs/zlib.make.log 2>&1 && make install > $B/logs/zlib.install.log 2>&1 ) \
    && ok zlib || { fail zlib; exit 1; }
fi
pkg libfontenc libfontenc-1.1.8.tar.xz            || exit 1
pkg libXfont   libXfont-1.5.4.tar.bz2 --disable-devel-docs --without-xmlto --without-fop || exit 1
# TinyX is a git snapshot: patch, autoreconf, then configure. Its old C needs
# gcc's permissive flags (implicit int and friends are errors in gcc 14+).
if ! done_or tinyx; then
  if [ ! -d $B/src/tinyx ]; then
    src tinyx tinyx-feab72c.tar.gz
    for p in $T/patches/tinyx-*.patch; do patch -p1 -d $B/src/tinyx < $p > /dev/null || { echo "patch $p failed"; exit 1; }; done
  fi
  ( cd $B/src/tinyx && autoreconf -fi > $B/logs/tinyx.autoreconf.log 2>&1 \
      && ./configure --prefix=$P CFLAGS="-O2 -std=gnu99 -Wno-error=implicit-int -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=return-mismatch" > $B/logs/tinyx.configure.log 2>&1 \
      && make -w V=1 -j1 > $B/logs/tinyx.make.log 2>&1 && make install > $B/logs/tinyx.install.log 2>&1 ) \
    && ok tinyx || { fail tinyx; exit 1; }
fi
for n in st-0.9.2 dwm-6.5; do src $n $n.tar.gz; done

# --- JWM and the Athena-widget apps for its menu ---
# Static libraries: pkg-config must hand configure the private libraries too,
# or the apps' link fails on Xft's fontconfig, Xt's SM and so on.
export PKG_CONFIG="pkg-config --static"
pkg libICE     libICE-1.1.1.tar.xz --disable-docs --disable-specs --without-xmlto --without-fop || exit 1
pkg libSM      libSM-1.2.4.tar.xz --disable-docs --without-libuuid --without-xmlto --without-fop || exit 1
# Xt's resource search path is compiled in. The default is built from
# --prefix, a path on the build host; this one is where the bundle puts
# app-defaults on the target.
pkg libXt      libXt-1.3.1.tar.xz --disable-specs --without-xmlto --without-fop \
  --with-xfile-search-path='/usr/share/X11/%L/%T/%N%C%S:/usr/share/X11/%T/%N%C%S:/usr/share/X11/%L/%T/%N%S:/usr/share/X11/%T/%N%S' || exit 1
# Xmu finds bitmaps (the apps' icons) in BITMAPDIR: the target's, where the
# bundle puts xbitmaps, not $P/include.
MK='BITMAP_DEFINES=-DBITMAPDIR=\"/usr/include/X11/bitmaps\"' \
pkg libXmu     libXmu-1.2.1.tar.xz --disable-docs --without-xmlto --without-fop || exit 1
pkg libXpm     libXpm-3.5.17.tar.xz --disable-open-zfile --disable-stat-zfile || exit 1
pkg libXaw     libXaw-1.0.16.tar.xz --disable-xaw6 --disable-specs --without-xmlto --without-fop || exit 1
# The apps: app-defaults install under the prefix; make_bundle.sh copies
# them to /usr/share/X11/app-defaults, which libXt above searches.
pkg xclock     xclock-1.1.1.tar.xz --without-xkb || exit 1
pkg xcalc      xcalc-1.1.2.tar.xz              || exit 1
pkg xeyes      xeyes-1.1.2.tar.bz2             || exit 1
pkg xload      xload-1.2.0.tar.xz --disable-nls || exit 1
# xedit's Lisp loads its .lsp files from LISPDIR at start-up. With the build
# prefix compiled in, it found none on the target, and its error path then
# longjmps through a buffer not yet set (a SIGSEGV in the gcc build too).
MK='LISPDIR=/usr/lib/X11/xedit/lisp' \
pkg xedit      xedit-1.2.4.tar.xz              || exit 1
# JWM looks for its libraries with AC_CHECK_LIB, not pkg-config, so a static
# link test needs the whole chain in LIBS. Its Makefile then links with
# `$(OBJECTS) $(LDFLAGS)` and never reads LIBS, so the chain goes into LDFLAGS
# too (configure's own tests put LDFLAGS before the test object, where the
# libraries resolve nothing, so it is harmless there). No PNG/JPEG/cairo/
# rsvg/pango/Xinerama; Xft, Xrender, XPM icons, SHAPE and Xmu are on.
JWMLIBS="-lXft -lXrender -lfontconfig -lfreetype -lexpat -lXpm -lXmu -lXt -lSM -lICE -lXext -lX11 -lxcb -lXau -lm -lpthread"
pkg jwm        jwm-2.4.6.tar.xz --disable-png --disable-cairo --disable-rsvg --disable-jpeg \
  --disable-pango --disable-xinerama --disable-nls --enable-xft --enable-xrender --enable-xpm \
  --enable-shape --enable-xmu CPPFLAGS="-I$P/include -I$P/include/freetype2" LDFLAGS="-L$P/lib $JWMLIBS" \
  LIBS="$JWMLIBS" || exit 1
echo "gcc reference build done"
