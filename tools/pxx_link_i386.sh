#!/bin/sh
# Link pxx i386 objects into a static executable with the host binutils:
#   tools/pxx_link_i386.sh [--shared-runtime] -o OUT obj.o [obj.o ...]
# The objects come from `pascal26 --target=i386 --emit-obj`. No libc is
# linked: by default each object carries its own copy of the C runtime.
# With --shared-runtime, the objects were built with --shared-runtime (they
# carry only their own code) and this script compiles the ONE runtime object
# they share (pxx/runtime_all.h, as `pascal26 --link` does on x86-64), using
# $PXX or else the compiler next to this script. For a multi-object program
# that is the size difference: toybox 0.8.15 i386 is 167 MB self-contained,
# 11.6 MB shared.
# The entry is tools/pxxcrt_i386.S (read its header for what it provides).
# `pascal26 --link` cannot do this: it reads ELF64 only.
# Needs `as --32` and `ld -m elf_i386` (stock x86-64 GNU binutils have both).
# feature-c-i386-link-for-c-objects
set -e
here=$(cd "$(dirname "$0")" && pwd)
shared=0
if [ "$1" = "--shared-runtime" ]; then shared=1; shift; fi
if [ "$1" != "-o" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "usage: $0 [--shared-runtime] -o OUT obj.o [obj.o ...]" >&2
  exit 2
fi
out=$2
shift 2
crt=$out.pxxcrt_i386.o
as --32 "$here/pxxcrt_i386.S" -o "$crt"
rto=
if [ $shared = 1 ]; then
  pxx=${PXX:-$here/../compiler/pascal26}
  rtc=$out.pxxrt_i386.c
  rto=$out.pxxrt_i386.o
  printf '#include <pxx/runtime_all.h>\n' > "$rtc"
  "$pxx" --target=i386 --emit-obj "$rtc" "$rto" > /dev/null
  rm -f "$rtc"
fi
status=0
ld -m elf_i386 -nostdlib -static -o "$out" "$crt" "$@" $rto || status=$?
rm -f "$crt"
if [ -n "$rto" ]; then rm -f "$rto"; fi
exit $status
