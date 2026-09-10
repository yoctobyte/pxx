#!/bin/sh
# Link pxx objects into an executable with NO external library: no libc, no
# crt1.o, no dynamic loader. This is the GOAL-5 link -- "have busybox compile as
# demo without external libraries" (owner, 2026-09-10) -- and it is a different
# link from the one tools/busybox_diff.sh performs.
#
#   tools/link_freestanding.sh <objdir-or-objects...> -o <out>
#
# WHY THIS IS NOT busybox_diff.sh's LINK, AND WHY BOTH ARE RIGHT. That harness
# links with `gcc`, which is correct for what it measures: it compares pxx's
# CODE against gcc's over a case list, and holding the libc constant is how the
# comparison stays about the compiler. Its GREEN is therefore a claim about
# compilation, NOT about freestanding linkability, and reading it as the latter
# is the house failure mode -- an instrument that is correct about something
# else. This script makes the other claim, and it asserts it rather than
# assuming it: the result must come out static with no interpreter.
#
# WHAT THE ENTRY HAS TO DO is in tools/pxx_freestanding_start.s, and it is more
# than reading argc/argv -- see the comment there. Summarised: four things, and
# the one that bites is .init_array.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
START="$ROOT/tools/pxx_freestanding_start.s"
OUT=""; OBJS=""

while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2 ;;
    *)  OBJS="$OBJS $1"; shift ;;
  esac
done

die() { echo "link-freestanding: $*" >&2; exit 1; }
[ -n "$OUT" ]  || die "no -o <out> given"
[ -n "$OBJS" ] || die "no objects given"
[ -f "$START" ] || die "no entry stub at $START"
command -v as >/dev/null || die "needs an assembler (as) for the entry stub"
command -v ld >/dev/null || die "needs ld"

# A directory argument means every object in it.
EXPANDED=""
for o in $OBJS; do
  if [ -d "$o" ]; then
    for f in "$o"/*.o; do [ -f "$f" ] && EXPANDED="$EXPANDED $f"; done
  else
    EXPANDED="$EXPANDED $o"
  fi
done
N=$(printf '%s\n' $EXPANDED | wc -l)
[ "$N" -ge 1 ] || die "the object list expanded to nothing"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pxxfs-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

as --64 -o "$TMP/start.o" "$START" || die "could not assemble $START"
ld -static -e _start -o "$OUT" "$TMP/start.o" $EXPANDED \
  || die "the freestanding link failed -- an undefined symbol here is a crtl gap, \
not a linker problem, because there is no second library to fall back on"

# ASSERTED, NOT ASSUMED. `ld -static` is a request, and a link that silently
# acquired an interpreter would be a dynamic executable wearing this script's
# name -- and `file` calls both of them "ELF 64-bit LSB executable".
readelf -l "$OUT" 2>/dev/null | grep -q 'INTERP' \
  && die "the result has a PT_INTERP -- it needs a dynamic loader, so it is not freestanding"
ldd "$OUT" 2>&1 | grep -q 'not a dynamic executable' \
  || die "ldd does not call this a static binary -- it links something"

printf 'link-freestanding: %s objects + the entry stub -> %s (%s bytes, static, no libc)\n' \
  "$N" "$OUT" "$(stat -c%s "$OUT")"
