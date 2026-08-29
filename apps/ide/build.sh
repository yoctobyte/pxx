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

"$PXX" \
  $GTK3_INC \
  -Fu"$ROOT/lib/pcl" \
  -Fu"$ROOT/lib/rtl" \
  -Fu"$ROOT/apps/ide/garin" \
  "$ROOT/apps/ide/eliah/main.pas" \
  "$ROOT/apps/ide/eliah/eliah"

echo "built: apps/ide/eliah/eliah"
