#!/bin/sh
# wasm32 gap census over a corpus list.
#
# IT REPORTS THE DENOMINATOR, and that is the whole difference from cen4.sh.
# A source that fails BEFORE codegen -- `undefined variable (SYS_openat)`, a
# parse error, a missing unit -- produces no coverage report at all, so it
# counts as ZERO GAPS while never having been measured. On 2026-09-04 that was
# 209 of 300 sources, and a "5 programs with gaps" headline was 5 of 91, not
# 5 of 300. The number is a rate and the rate needs its denominator printed
# beside it, every time.
if [ $# -lt 2 ]; then
  echo "usage: tools/wasm32_gap_census.sh <report-out> <list-of-sources>" >&2
  echo "  build a list with e.g.:  ls test/*.pas > /tmp/list.txt" >&2
  exit 2
fi
out=$1
: > "$out"
n=0
while IFS= read -r f <&3; do
  [ -f "$f" ] || continue
  n=$((n+1))
  echo "### $f" >> "$out"
  ./compiler/pascal26 --target=wasm32 "$f" /tmp/cen5.wasm >> "$out" 2>&1 </dev/null
done 3< "$2"
python3 - "$out" "$n" <<'PY'
import io,sys
blocks={}; cur=None
for ln in io.open(sys.argv[1],encoding='utf-8',errors='replace'):
    if ln.startswith('### '): cur=ln[4:].strip(); blocks[cur]=[]
    elif cur is not None: blocks[cur].append(ln)
tot=len(blocks)
reached=[k for k,b in blocks.items() if any(l.startswith('ok:') for l in b)]
gaps=[k for k in reached if any('distinct gap(s) seen' in l for l in blocks[k])]
print("sources attempted:            %d" % int(sys.argv[2]))
print("REACHED THE wasm32 BACKEND:   %d   <-- the denominator" % len(reached))
print("failed before codegen:        %d   (never measured; not zero gaps)" % (tot-len(reached)))
print("  of those reached, clean:    %d" % (len(reached)-len(gaps)))
print("  of those reached, w/ gaps:  %d" % len(gaps))
PY
