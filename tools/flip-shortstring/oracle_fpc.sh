#!/bin/sh
# The FPC ORACLE for the shortstring flip. For every test that declares
# string[N]/shortstring, ask FPC 3.2.2 what the program prints -- FPC's
# shortstring is the reference the flip is trying to reach -- and record it
# beside the pxx off/on outputs the sweep already saved.
#
# A row where pxx-off and pxx-on AGREE needs no oracle. A row where they differ
# is the whole question, and the oracle answers it: whichever mode matches FPC
# is the one the flip should produce.
#
# FPC cannot build every one of these (pxx dialect, pxx-only units, pxx
# intrinsics). Those rows are reported NO-ORACLE, never silently dropped.
set -u
OUT="$1"; D="$2"
: > "$OUT"
for f in $(grep -lEi 'string\[[0-9]+\]|\bshortstring\b' test/[a-z]*.pas); do
  b=$(basename "$f" .pas)
  w="$D/fpc.$b"; mkdir -p "$w"
  cp "$f" "$w/$b.pas"
  ok=0
  for m in "-Mobjfpc" "-Mfpc" "-Mdelphi"; do
    if (cd "$w" && fpc $m -vw -Fu"$OLDPWD/test" -o"$b.bin" "$b.pas" > fpc.log 2>&1); then ok=1; break; fi
  done
  if [ "$ok" = 0 ]; then
    echo "$b	NO-ORACLE	$(grep -m1 -i 'error' "$w/fpc.log" | cut -c1-100)" >> "$OUT"; continue
  fi
  timeout 60 "$w/$b.bin" > "$w/$b.fpc.out" 2>&1; rc=$?
  echo "$b	FPC-OK	rc=$rc	mode=$m" >> "$OUT"
done
echo "DONE fpc" >> "$OUT"
