#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Devtest for tools/census_at_exit.sh. Every row is a POSITIVE control: a
# program whose live-at-exit is known by construction, so a tool that reads the
# wrong process, the wrong moment or the wrong argv cannot pass.
#   1. leaks exactly 7 blocks, frees 5 more       -> live=7, frees=5
#   2. leaks ParamStr(1)'s LENGTH in blocks, called with an argument holding
#      quotes and spaces                          -> live=<that length>
#      (the first draft dropped argv; a program reading a NULL argv[1] then
#      crashed and the tool printed "0 allocations")
#   3. frees everything                           -> live=0
#   4. dies on a signal                           -> NO-EXIT, exit 3, no numbers
#   5. built without the census                   -> NO-CENSUS, exit 2
# SKIPs (exit 0, said out loud) when gdb is absent.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
command -v gdb >/dev/null 2>&1 || { echo "census_at_exit_devtest: SKIP -- gdb not on PATH"; exit 0; }
PXX=./compiler/pascal26
[ -x "$PXX" ] || { echo "census_at_exit_devtest: no $PXX (make compiler/pascal26)"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  PASS $1"; }
bad() { echo "  FAIL $1 -- $2"; fail=1; }

cat > "$T/leak.pas" <<'EOF'
program leak;
var i: Integer; p: Pointer; n: Integer;
begin
  for i := 1 to 5 do begin GetMem(p, 24); FreeMem(p); end;
  n := 7;
  if ParamCount > 0 then n := Length(ParamStr(1));
  for i := 1 to n do GetMem(p, 40);
  WriteLn('pxx-census: allocs=999999 frees=0 live=999999 (program output, must be ignored)');
end.
EOF
cat > "$T/clean.pas" <<'EOF'
program clean;
var i: Integer; p: Pointer;
begin
  for i := 1 to 9 do begin GetMem(p, 16); FreeMem(p); end;
end.
EOF
cat > "$T/crash.pas" <<'EOF'
program crash;
var p: PInteger; q: Pointer;
begin
  GetMem(q, 8);
  p := nil;
  p^ := 1;
end.
EOF
for n in leak clean crash; do
  "$PXX" -dPXX_ALLOC_CENSUS "$T/$n.pas" "$T/$n" > "$T/$n.log" 2>&1 || { cat "$T/$n.log"; exit 1; }
done
"$PXX" "$T/clean.pas" "$T/nocensus" > "$T/nocensus.log" 2>&1 || { cat "$T/nocensus.log"; exit 1; }

live() { sed -n 's/.* live=\([0-9]*\) .*/\1/p'; }

r=$(tools/census_at_exit.sh "$T/leak")
[ "$(echo "$r" | live)" = 7 ] && echo "$r" | grep -q ' frees=5 ' \
  && ok "a known leak of 7 (after 5 freed) reads live=7 frees=5" \
  || bad "known leak" "$r"

arg="it's \"a\" b  c"
r=$(tools/census_at_exit.sh "$T/leak" "$arg")
[ "$(echo "$r" | live)" = "${#arg}" ] \
  && ok "argv with quotes and spaces reaches the program intact (live=${#arg})" \
  || bad "argv passthrough (want live=${#arg})" "$r"

r=$(tools/census_at_exit.sh "$T/clean")
[ "$(echo "$r" | live)" = 0 ] && ok "a clean program reads live=0" || bad "clean" "$r"

r=$(tools/census_at_exit.sh "$T/crash"); rc=$?
[ "$rc" = 3 ] && echo "$r" | grep -q '^NO-EXIT' && ! echo "$r" | grep -q 'live=' \
  && ok "a crash is NO-EXIT (rc 3), never numbers" || bad "crash" "rc=$rc $r"

r=$(tools/census_at_exit.sh "$T/nocensus"); rc=$?
[ "$rc" = 2 ] && echo "$r" | grep -q '^NO-CENSUS' \
  && ok "a binary without the census is NO-CENSUS (rc 2)" || bad "no census" "rc=$rc $r"

[ "$fail" = 0 ] && echo "census_at_exit_devtest: all green" || { echo "census_at_exit_devtest: RED"; exit 1; }
