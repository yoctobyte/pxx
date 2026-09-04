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
#
# AND IT VALIDATES THE MODULE, which is a DIFFERENT instrument from counting
# coverage-report lines. A gap produces a report line; an invalid ENCODING does
# not. Measured 2026-09-04: every wasm32 module carrying a Variant-boxed string
# had `local.set -1` in it, the compile printed `ok:` and exited 0, no gap was
# recorded, and no loader would take the module. A census that reads only the
# report scores that source as CLEAN. `wasm-validate` is required, not skipped
# when missing: a bucket that silently cannot fill is the same animal as the
# hole it was added to close.
if [ $# -lt 2 ]; then
  echo "usage: tools/wasm32_gap_census.sh <report-out> <list-of-sources>" >&2
  echo "  build a list with e.g.:  ls test/*.pas > /tmp/list.txt" >&2
  exit 2
fi
if ! command -v wasm-validate >/dev/null 2>&1; then
  echo "wasm32_gap_census: wasm-validate not found (wabt)." >&2
  echo "  The invalid-ENCODING bucket cannot be filled without it, and a census" >&2
  echo "  that quietly drops that bucket reports every such source as CLEAN." >&2
  exit 2
fi
out=$1
: > "$out"
# THE POPULATION AND THE BINARY, IN THE REPORT ITSELF. The 2026-09-03 run
# recorded "300 sources from the test corpus" and did not say WHICH 300, so
# nobody -- including its author -- could re-run it or diff a row breakdown
# against it. A census whose population is not written down is a number without
# a denominator all over again, one level up. The compiler's sha names the
# binary and the commit names what built it; neither alone is an identity.
{
  echo "### CENSUS-META"
  echo "date:     $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "list:     $2"
  echo "sources:  $(grep -c . "$2")"
  echo "compiler: $(sha256sum ./compiler/pascal26 2>/dev/null | cut -c1-16)"
  echo "commit:   $(git rev-parse --short=12 HEAD 2>/dev/null)  $(git status --porcelain 2>/dev/null | grep -q . && echo '(TREE DIRTY)' || echo '(tree clean)')"
  echo "--- the list, verbatim ---"
  cat "$2"
  echo "--- end of list ---"
} >> "$out"
tmpw=$(mktemp -d)
n=0
while IFS= read -r f <&3; do
  [ -f "$f" ] || continue
  n=$((n+1))
  echo "### $f" >> "$out"
  rm -f "$tmpw/m.wasm"
  ./compiler/pascal26 --target=wasm32 "$f" "$tmpw/m.wasm" >> "$out" 2>&1 </dev/null
  # ONLY when a module was actually WRITTEN. Asserting the precondition, not
  # just the check: validating a file that does not exist reports a failure
  # that belongs to the compile, and the two buckets would merge.
  if [ -f "$tmpw/m.wasm" ]; then
    if wasm-validate "$tmpw/m.wasm" >> "$out" 2>&1; then :; else
      echo "CENSUS-INVALID-MODULE" >> "$out"
    fi
  fi
done 3< "$2"
rm -rf "$tmpw"
python3 - "$out" "$n" <<'PY'
import io,sys
blocks={}; cur=None
for ln in io.open(sys.argv[1],encoding='utf-8',errors='replace'):
    if ln.startswith('### '):
        cur=ln[4:].strip()
        # The meta header is a `### ` block and is NOT a source. Left in the
        # dict it has no `ok:` line and lands in `failed before codegen`,
        # which is how a header quietly became a compile failure: 13 -> 14 on
        # a 20-source list, the first run after it was added.
        if cur == 'CENSUS-META': cur=None
        else: blocks[cur]=[]
    elif cur is not None: blocks[cur].append(ln)
tot=len(blocks)
reached=[k for k,b in blocks.items() if any(l.startswith('ok:') for l in b)]
gaps=[k for k in reached if any('distinct gap(s) seen' in l for l in blocks[k])]
bad=[k for k in reached if any(l.startswith('CENSUS-INVALID-MODULE') for l in blocks[k])]
clean=[k for k in reached if k not in gaps and k not in bad]
print("sources attempted:            %d" % int(sys.argv[2]))
print("REACHED THE wasm32 BACKEND:   %d   <-- the denominator" % len(reached))
print("failed before codegen:        %d   (never measured; not zero gaps)" % (tot-len(reached)))
print("  of those reached, clean:    %d   (compiled AND validated)" % len(clean))
print("  of those reached, w/ gaps:  %d" % len(gaps))
print("  of those reached, INVALID:  %d   (compiled ok, module rejected)" % len(bad))
for k in bad:
    print("      invalid: %s" % k)
PY
