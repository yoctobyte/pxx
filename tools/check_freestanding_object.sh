#!/bin/bash
# check_freestanding_object.sh OBJ EXPORTED_FN
#
# The properties `--emit-obj --freestanding` promises, read off the object
# with readelf: no .init_array/.fini_array, .bss under 4 KiB, no crtl
# implementation (strlen/strsignal bodies), EXPORTED_FN defined and global,
# strlen left undefined. Prints "freestanding object ok" or what failed.
set -u
O=$1; FN=$2
fail=0
sec=$(readelf -SW "$O")
if echo "$sec" | grep -qE '\.(init|fini)_array'; then echo "FAIL: has an init/fini array"; fail=1; fi
bsshex=$(readelf -SW "$O" | awk '{for (i = 1; i < NF; i++) if ($i == ".bss") print $(i + 4)}')
bss=''
[ -n "$bsshex" ] && bss=$((16#$bsshex))
if [ -z "$bss" ] || [ "$bss" -ge 4096 ]; then echo "FAIL: .bss is ${bss:-missing} bytes"; fail=1; fi
syms=$(readelf -sW "$O")
if echo "$syms" | awk '$7!="UND" {print $8}' | grep -qxE 'strlen|strsignal'; then echo "FAIL: a crtl body is in the object"; fail=1; fi
if ! echo "$syms" | awk '$5=="GLOBAL" && $7!="UND" {print $8}' | grep -qx "$FN"; then echo "FAIL: $FN is not exported"; fail=1; fi
if ! echo "$syms" | awk '$7=="UND" {print $8}' | grep -qx strlen; then echo "FAIL: strlen is not an undefined import"; fail=1; fi
[ $fail = 0 ] && echo "freestanding object ok"
exit $fail
