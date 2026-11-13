#!/bin/bash
# check_extern_bss.sh <compiler> <workprefix>
# Gibux item 6: an object that only declares big extern arrays reserves no
# .bss for them, and every variable that moved down is still addressed right.
#   1. the declaring object's .bss is smaller than the two imports together
#      (326,144 bytes): with the slots reserved it can never be;
#   2. linked by pxx (--link) its output is the expected one;
#   3. linked by gcc (the oracle: a third-party linker reads the same objects)
#      the output is the same.
set -u
PXX=$1; W=$2
fail() { echo "check_extern_bss: FAIL: $*"; exit 1; }
"$PXX" --emit-obj test/c_extern_array_reserves_no_bss_use.c "$W"_use.o > /dev/null || fail "compile use"
"$PXX" --emit-obj test/c_extern_array_reserves_no_bss_def.c "$W"_def.o > /dev/null || fail "compile def"
sz=$(readelf -SW "$W"_use.o | sed -n 's/.*\] \.bss  *NOBITS  *[0-9a-f]*  *[0-9a-f]*  *\([0-9a-f]*\).*/\1/p')
[ -n "$sz" ] || fail "no .bss in the declaring object"
[ $((16#$sz)) -lt 326144 ] || fail ".bss of the declaring object is 0x$sz: the import slots are still reserved"
exp=$(cat test/c_extern_array_reserves_no_bss.expected)
"$PXX" --link -o "$W"_pxx "$W"_use.o "$W"_def.o > /dev/null || fail "pxx --link"
got=$("$W"_pxx) || fail "pxx-linked program exited $?"
[ "$got" = "$exp" ] || fail "pxx-linked output differs:
$got"
if command -v gcc > /dev/null; then
  gcc -no-pie -o "$W"_gcc "$W"_use.o "$W"_def.o 2> /dev/null && {
    got=$("$W"_gcc) || fail "gcc-linked program exited $?"
    [ "$got" = "$exp" ] || fail "gcc-linked output differs:
$got"
  }
fi
echo "check_extern_bss: OK (.bss 0x$sz)"
