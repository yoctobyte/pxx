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
pkg() {   # name tarball [configure args...]
  n=$1; t=$2; shift 2
  done_or $n && return 0
  src $n $t
  ( cd $B/src/$n && ./configure $CFG "$@" > $B/logs/$n.configure.log 2>&1 \
      && make -w V=1 -j1 > $B/logs/$n.make.log 2>&1 \
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
echo "gcc reference build done"
