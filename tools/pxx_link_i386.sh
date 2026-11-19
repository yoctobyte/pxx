#!/bin/sh
# Link pxx i386 objects into a static executable with the host binutils:
#   tools/pxx_link_i386.sh -o OUT obj.o [obj.o ...]
# The objects come from `pascal26 --target=i386 --emit-obj` and carry their
# own C runtime, so no libc is linked. The entry is tools/pxxcrt_i386.S (read
# its header for what it provides and what it does not).
# `pascal26 --link` cannot do this: it reads ELF64 only.
# Needs `as --32` and `ld -m elf_i386` (stock x86-64 GNU binutils have both).
# feature-c-i386-link-for-c-objects
set -e
if [ "$1" != "-o" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "usage: $0 -o OUT obj.o [obj.o ...]" >&2
  exit 2
fi
out=$2
shift 2
here=$(cd "$(dirname "$0")" && pwd)
crt=$out.pxxcrt_i386.o
as --32 "$here/pxxcrt_i386.S" -o "$crt"
status=0
ld -m elf_i386 -nostdlib -static -o "$out" "$crt" "$@" || status=$?
rm -f "$crt"
exit $status
