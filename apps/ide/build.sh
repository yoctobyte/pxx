#!/usr/bin/env bash
# Build Eliah (GTK face) with the pinned stable compiler. Track B: never rebuilds
# the compiler.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PXX="${PXX_STABLE:-$ROOT/stable_linux_amd64/default/pinned}"

test -x "$PXX" || { echo "No stable compiler at $PXX" >&2; exit 1; }

# The GTK3 include root, same definition as tools/gui_suite.sh and the Makefile.
# It was MISSING here, and that was not cosmetic: lib/pcl/gtk3_c.h is
# `#include <gtk/gtk.h>`, gtk-2.0 is a default system include root and gtk-3.0
# is not, so eliah was being compiled against GTK2 headers -- while linking
# libgtk-3.so.0, because CHeaderStem derives the link stem from the unit name
# and not from -I. Header/library ABI mismatch, silent: sizeof(GtkWidget) is 96
# under GTK2 headers and 32 under GTK3. Nothing complained, because nothing
# checked; the binding now asserts its version, which is what surfaced this.
# feature-b-pcl-should-assert-its-gtk-version-rather-than-rely-on-an-accident
GTK3_INC="$(pkg-config --cflags-only-I gtk+-3.0 2>/dev/null || true)"
[ -n "$GTK3_INC" ] || GTK3_INC="-I/usr/include/gtk-3.0/"

# -Fu roots BEFORE the include root, and this is a FIX, not a tidy-up. A `uses X`
# is captured by a C header of the same stem found on an -I root that precedes
# the Pascal search, and becomes a dynamic import that compiles clean and dies at
# load on a nonexistent libX.so
# (bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import;
# fixed compiler-side in 4576ad4d1, which pin v393 predates).
#
# This script HAD the include root first, and GTK3_INC carries
# /usr/include/libpng16, which collides with lib/rtl/png.pas. Measured on v393:
#   pinned -I/usr/include/libpng16 -Fulib/rtl   -> undefined variable (PngLastError)
#   pinned -Fulib/rtl -I/usr/include/libpng16   -> ok
# so the exposure was real, not hypothetical.
#
# It does NOT take a header we ship -- libpng's is not ours. An earlier version
# of this comment claimed it did, from a probe that only asked "does it build":
# a bare `uses png` builds clean in BOTH orders and the arms are
# indistinguishable except in the size line (procs=1046 for libpng's ~1000
# declarations vs procs=293 for the Pascal unit). A witness must name a symbol
# only the Pascal unit provides.
"$PXX" \
  -Fu"$ROOT/lib/pcl" \
  -Fu"$ROOT/lib/rtl" \
  -Fu"$ROOT/apps/ide/garin" \
  $GTK3_INC \
  "$ROOT/apps/ide/eliah/main.pas" \
  "$ROOT/apps/ide/eliah/eliah"

echo "built: apps/ide/eliah/eliah"
