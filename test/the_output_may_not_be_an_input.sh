#!/bin/sh
# THE OUTPUT MAY NOT BE AN INPUT, UNDER ANY SPELLING.
#
# `pxx g.pas ./g.pas`, the absolute path, `a/../g.pas` and a symlink to the
# source all wrote the ELF over the source file; only the byte-identical
# `pxx g.pas g.pas` was caught, because the guard compared spellings. The same
# held for a unit or a C header the compile reads. v445 (caf21ac399f1)
# clobbers every row below but the byte-identical one.
# bug-a-the-output-can-overwrite-the-source-under-another-spelling
#
# Each refusal row asserts BOTH halves: pxx exits nonzero naming the collision,
# AND the input is byte-identical afterwards. The positive rows prove the guard
# is not a blanket refusal: a fresh output builds, a rebuild over an existing
# (non-input) output builds, and `pxx g` with no extension still defaults to
# `g.out`.
#
# Also here: --no-lazy-var's error named `--lazy-var`, an option pxx rejects.
#
# usage: sh test/the_output_may_not_be_an_input.sh <compiler> <tmpdir>
PXX=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
T=$(mktemp -d "$2/outin.XXXXXX") || exit 1
cd "$T" || exit 1
fail=0
MSG='the output is an input of this compile'

printf 'program g; begin WriteLn(42); end.\n' > g.pas.orig
printf 'unit u; interface function F: Integer; implementation function F: Integer; begin F := 7; end; end.\n' > u.pas.orig
printf 'program h; uses u; begin WriteLn(F); end.\n' > h.pas
printf '#include "inc.h"\nint main(void) { return X; }\n' > c.c.orig
printf '#define X 3\n' > inc.h.orig
mkdir a

# refused <label> <file-that-must-survive> <orig> <pxx args...>
refused() {
  label=$1; keep=$2; orig=$3; shift 3
  "$PXX" "$@" > out.txt 2>&1; rc=$?
  if [ $rc -ne 0 ] && grep -q "$MSG" out.txt && cmp -s "$keep" "$orig"; then
    echo "ok   $label: refused, $keep intact"
  else
    echo "FAIL $label: rc=$rc, $keep $(cmp -s "$keep" "$orig" && echo intact || echo CLOBBERED)"
    sed -n 1,3p out.txt
    fail=1
  fi
}

for o in g.pas ./g.pas "$T/g.pas" a/../g.pas; do
  cp g.pas.orig g.pas
  refused "pascal source as output '$o'" g.pas g.pas.orig g.pas "$o"
done
cp g.pas.orig g.pas; ln -s g.pas sym.pas
refused "a symlink to the source" g.pas g.pas.orig g.pas sym.pas
cp g.pas.orig g.pas; ln g.pas hard.pas
refused "a hard link to the source" g.pas g.pas.orig g.pas hard.pas
cp g.pas.orig g.pas
refused "the source by a different path to it" g.pas g.pas.orig ./a/../g.pas g.pas
cp u.pas.orig u.pas
refused "a used unit as output" u.pas u.pas.orig h.pas ./u.pas
cp c.c.orig c.c; cp inc.h.orig inc.h
refused "a C source as output" c.c c.c.orig c.c ./c.c
refused "a C header as output" inc.h inc.h.orig c.c ./inc.h

# positive rows: the guard refuses collisions, not builds
cp g.pas.orig g.pas
if "$PXX" g.pas gout > out.txt 2>&1 && [ "$(./gout)" = 42 ] &&
   "$PXX" g.pas gout > out.txt 2>&1 && [ "$(./gout)" = 42 ]; then
  echo "ok   a fresh output, then a rebuild over it, both build and run"
else
  echo "FAIL a fresh output or its rebuild"; sed -n 1,3p out.txt; fail=1
fi
cp g.pas.orig noext
if "$PXX" noext > out.txt 2>&1 && [ "$(./noext.out)" = 42 ] && cmp -s noext g.pas.orig; then
  echo "ok   a defaulted output equal to the source becomes .out"
else
  echo "FAIL the defaulted .out output"; sed -n 1,3p out.txt; fail=1
fi

printf 'program lv; begin var x: Integer := 3; WriteLn(x); end.\n' > lv.pas
"$PXX" --no-lazy-var lv.pas lv > out.txt 2>&1
if grep -q 'disabled by --no-lazy-var' out.txt && ! grep -q 'use --lazy-var' out.txt; then
  echo "ok   --no-lazy-var's error names the option that was passed"
else
  echo "FAIL --no-lazy-var's error"; sed -n 1,2p out.txt; fail=1
fi

[ $fail -eq 0 ] && echo "THE OUTPUT MAY NOT BE AN INPUT OK"
exit $fail
