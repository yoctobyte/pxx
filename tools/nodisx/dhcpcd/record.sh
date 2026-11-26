#!/bin/sh
# record.sh: write the dhcpcd recipe (the DHCPv4/v6, IPv4LL and IPv6 RA
# client the installer brings the network up with) that onsite.sh replays on
# the target.
#
# HOST SIDE, the only step that needs gcc. dhcpcd has its own hand-written
# configure (not autoconf) and a BSD-style Makefile; both run here ONCE, and
# what they decided travels in the recipe, PRE-GENERATED:
#   gen.tar   config.h; src/dhcpcd-embedded.{c,h} (the option definitions,
#             made by genembedc/genembedh); hooks/dhcpcd-run-hooks (sed over
#             the .in file), hooks/30-hostname (the same, from 30-hostname.in)
#   units     one line per object (../lib/units-from-make.sh, from the make log)
#   link      dhcpcd's objects
# The choices, given here rather than probed from this host:
#   --without-udev     no udev on Nodisx: dhcpcd watches netlink itself
#   --without-openssl  dhcpcd's own md5/sha256/hmac (compat/crypt), no libcrypto
#   --disable-privsep  privilege separation needs a dedicated user, a chroot
#                      directory and seccomp filters; the install environment
#                      runs as root with none of them. A SECURITY TRADE-OFF,
#                      to revisit for the installed system.
#   --with-hooks= --with-eghooks=
#                      only the three base hooks (01-test, 20-resolv.conf,
#                      30-hostname). configure otherwise adds an NTP or NIS
#                      hook if THIS host has chronyd/ntpd/ypbind installed.
# Everything else configure checks (arc4random, strlcpy, reallocarray,
# open_memstream, the netlink and nl80211 headers) crtl provides; a crtl change
# that removes one shows up as a compile error on site.
# The gcc build stays in $W/dhcpcd-ref for test.sh.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/dhcpcd/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TARBALL=dhcpcd-10.5.2.tar.xz
"$T/../fetch.sh" "$TARBALL" > /dev/null
REF=$W/dhcpcd-ref
R=$W/recipe/dhcpcd
rm -rf "$REF" "$R"
mkdir -p "$REF" "$R"
xzcat "$W/dl/$TARBALL" | tar -xf - -C "$REF" --strip-components=1
cd "$REF"
CC=gcc ./configure --without-udev --without-openssl --disable-privsep \
  --with-hooks= --with-eghooks= > "$W/dhcpcd-configure.log" 2>&1
make -j3 > "$W/dhcpcd-build.log" 2>&1
[ -x src/dhcpcd ] || { echo "record: gcc build made no dhcpcd" >&2; exit 1; }

sum=$(sha256sum "$W/dl/$TARBALL" | cut -d' ' -f1)
echo "$TARBALL $sum" > "$R/sources.list"
sh "$T/../lib/units-from-make.sh" "$REF" "$W/dhcpcd-build.log" dhcpcd \
  | awk -v u="$R/units" -v l="$R/link" '/^%%$/ { s = 1; next } { print > (s ? l : u) }'
grep -q 'MISSING-ARCHIVE' "$R/link" && { echo "record: an archive on the link line was not built in the log" >&2; exit 1; }
grep -q "$REF" "$R/units" "$R/link" && { echo "record: a host path is left in the recipe" >&2; exit 1; }
tar -cf "$R/gen.tar" config.h src/dhcpcd-embedded.c src/dhcpcd-embedded.h hooks/dhcpcd-run-hooks hooks/30-hostname
cp "$T/onsite.sh" "$R/onsite.sh"
git -C "$T" rev-parse HEAD > "$R/RECIPE" 2>/dev/null || echo unknown > "$R/RECIPE"
echo "recipe: $R ($(wc -l < "$R/units") units; dhcpcd links $(($(wc -w < "$R/link") - 1)) objects)"
