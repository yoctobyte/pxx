#!/bin/bash
# check_proc_map.sh COMPILER TMPDIR
# --proc-map must give the same address as the --map file, which writeELF fills
# from the code offset it really used, for a static AND a dynamic (libc-import)
# x86-64 build. Until 2026-11-19 --proc-map recomputed the offset from
# CODE_OFFSET and every line of a dynamic build was 0x70 low.
# bug-a-proc-map-emits-static-addresses-for-a-dynamic-build
set -e
cc=$1
t=$2
printf 'program pm;\nprocedure Foo; begin Writeln(1); end;\nbegin Foo; end.\n' > "$t/pm_static.pas"
printf 'program pm;\nfunction getpid: LongInt; cdecl; external \x27libc.so.6\x27;\nprocedure Foo; begin Writeln(getpid > 0); end;\nbegin Foo; end.\n' > "$t/pm_dyn.pas"
for v in static dyn; do
  "$cc" --proc-map --map "$t/pm_$v.pas" "$t/pm_$v" 2> "$t/pm_$v.procmap" > /dev/null
  pm=$(awk '$1 == "PROC" && $3 == "Foo" {print tolower($2)}' "$t/pm_$v.procmap")
  mp=$(awk '$2 == "Foo" {print tolower(substr($1, 11))}' "$t/pm_$v.map")
  echo "$v proc-map=$pm map=$mp"
  if [ -z "$pm" ] || [ "$pm" != "$mp" ]; then
    echo "FAIL: $v --proc-map address for Foo does not match the map file"
    exit 1
  fi
done
echo "PROC MAP OK"
