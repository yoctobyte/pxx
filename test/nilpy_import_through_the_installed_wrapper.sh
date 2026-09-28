# SPDX-License-Identifier: MPL-2.0
#
# Nil Python imports resolved through the INSTALLED ./pxx wrapper's root list.
#
# tools/install.sh writes a wrapper that passes every lib/ directory holding a
# unit source as -Fu -- lib/crtl/include and its subdirectories among them,
# after the Pascal roots. The bare compiler has none of those roots, so a
# resolution bug that only a -Fu root can cause is invisible to every row that
# calls ./$(COMPILER) directly: `import time` bound lib/crtl/include/time.h
# ahead of the mimic_time shim, on the path every doc tells a user to take.
#
# This builds a real wrapper with tools/install.sh (into the scratch dir, never
# over ./pxx) around the compiler under test, then compiles through it. The
# root list is therefore whatever install.sh computes today, not a copy of it.
#
# Usage: sh test/nilpy_import_through_the_installed_wrapper.sh <pxx> <tmpdir> <program.npy>
# The program is named by the Makefile row rather than here, so the wiring
# check sees it run.
set -e
PXX=${1:?usage: nilpy_import_through_the_installed_wrapper.sh <pxx> <tmpdir>}
TMP=${2:?usage: nilpy_import_through_the_installed_wrapper.sh <pxx> <tmpdir> <program.npy>}
SRC=${3:?usage: nilpy_import_through_the_installed_wrapper.sh <pxx> <tmpdir> <program.npy>}
case "$PXX" in /*) ;; *) PXX="$PWD/$PXX" ;; esac

WRAPDIR=$TMP/installed_wrapper
mkdir -p "$WRAPDIR"
tools/install.sh --bindir "$WRAPDIR" --compiler "$PXX" > "$TMP/installed_wrapper.log" 2>&1
if ! grep -q 'lib/crtl/include"' "$WRAPDIR/pxx"; then
  echo "FAIL: nilpy_import_through_the_installed_wrapper — the wrapper has no lib/crtl/include root, so this row no longer reproduces the install path it guards."
  exit 1
fi

T=${SRC%.npy}
"$WRAPDIR/pxx" "$T.npy" "$TMP/stdlib_via_wrapper" > "$TMP/stdlib_via_wrapper.log" 2>&1 || {
  echo "FAIL: nilpy_import_through_the_installed_wrapper — $T.npy did not compile through the wrapper:"
  grep -m3 'error' "$TMP/stdlib_via_wrapper.log" | sed 's/^/    /'
  exit 1
}
"$TMP/stdlib_via_wrapper" | diff -u "$T.expected" -

# utime is MicroPython's name (no CPython module), so it has no .expected
# line; it collided with lib/crtl/include/utime.h the same way.
printf 'import utime\nutime.sleep_ms(1)\nprint(utime.ticks_ms() >= 0)\n' > "$TMP/utime_via_wrapper.npy"
"$WRAPDIR/pxx" "$TMP/utime_via_wrapper.npy" "$TMP/utime_via_wrapper" > "$TMP/utime_via_wrapper.log" 2>&1 || {
  echo "FAIL: nilpy_import_through_the_installed_wrapper — import utime did not compile through the wrapper:"
  grep -m3 'error' "$TMP/utime_via_wrapper.log" | sed 's/^/    /'
  exit 1
}
[ "$("$TMP/utime_via_wrapper")" = True ]
echo "  test-nilpy: time/string/socket/utime resolve to their shims through the installed wrapper"
