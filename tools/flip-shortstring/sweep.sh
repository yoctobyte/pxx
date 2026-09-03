#!/bin/sh
# The phase-4 shortstring flip, measured BEFORE the flag is deleted.
# -dPXX_SHORTSTRING today IS the post-flip default, so "off" is the current
# tree and "on" is what the flip makes everyone get. Both modes only coexist
# until the flag goes, which is why this runs now.
set -u
OUT="$1"; D="$2"; T="$3"
: > "$OUT"
xflag=""; ext=""
[ "$T" = "xtensa" ] && xflag="--platform=posix --xtensa-soft-mulhigh"
[ "$T" = "wasm32" ] && ext=".wasm"
for f in $(grep -lEi 'string\[[0-9]+\]|\bshortstring\b' test/[a-z]*.pas); do
  b=$(basename "$f" .pas)
  off="$D/$T.$b.off$ext"; on="$D/$T.$b.on$ext"
  if ! ./compiler/pascal26 --target=$T $xflag "$f" "$off" > "$off.log" 2>&1; then
    echo "$b	BUILD-OFF-FAIL	$(grep -m1 -i error "$off.log" | cut -c1-100)" >> "$OUT"; continue
  fi
  if ! ./compiler/pascal26 --target=$T $xflag -dPXX_SHORTSTRING "$f" "$on" > "$on.log" 2>&1; then
    echo "$b	BUILD-ON-FAIL	$(grep -m1 -i error "$on.log" | cut -c1-100)" >> "$OUT"; continue
  fi
  timeout 60 tools/run_target.sh $T "$off" > "$off.out" 2>&1; rcoff=$?
  timeout 60 tools/run_target.sh $T "$on"  > "$on.out"  2>&1; rcon=$?
  if [ "$rcoff" != "$rcon" ]; then
    echo "$b	RC-DIFFERS	off=$rcoff on=$rcon" >> "$OUT"
  elif cmp -s "$off.out" "$on.out"; then
    echo "$b	SAME	rc=$rcoff" >> "$OUT"
  else
    echo "$b	OUTPUT-DIFFERS	rc=$rcoff" >> "$OUT"
  fi
done
echo "DONE $T" >> "$OUT"
