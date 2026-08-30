#!/bin/sh
# ParamCount / ParamStr / ArgStr on wasm32 (Phase 9j).
#
# WASI has no initial stack to walk, so unlike every register target the argv
# read is two host calls and an allocation rather than a load off saved $sp.
# The oracle is the NATIVE build handed the same arguments; the harness is
# node's own WASI, which is an independent preview1 implementation.
#
# Two cases are NOT diffed and live in argv_oob_slice.pas with written-out
# expectations instead, because native is not a usable oracle for either: the
# register targets disagree about out-of-range indices, and the native build
# corrupts its own frame on an argument longer than 256 bytes
# (bug-a-x86-64-paramstr-expression-smashes-its-frozen-temp, found here).
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-argv.$$
mkdir -p "$work/sandbox"
trap 'rm -rf "$work"' EXIT

# Chosen to break a naive implementation: an empty argument (a strlen that
# returns garbage rather than 0), one with a space (an argv walk that splits
# on whitespace instead of following the vector), and a long one (a fixed
# buffer sized by a guess rather than by args_sizes_get). 200 and not 300 --
# past 256 the ORACLE breaks, which is the ticket named above; the 300-byte
# case is asserted wasm-only below and moves back here once that is fixed.
long=$(printf 'x%.0s' $(seq 1 200))
set -- alpha '' 'two words' "$long" omega

"$root/compiler/pascal26" "$here/argv_slice.pas" "$work/prog" >/dev/null
"$work/prog" "$@" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/argv_slice.pas" "$work/w.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/w.wasm"

if grep -qE '^    main\$[0-9]' "$work/cov.txt"; then
  echo "FAIL a top-level chunk of this slice was emitted as unreachable:"
  grep -E '^    main\$[0-9]' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

node --no-warnings "$here/wasihost.js" "$work/w.wasm" "$work/sandbox" "$@" \
    > "$work/wasm.txt"

# A build that refuses argv and a build that produces nothing both leave an
# empty file, and diffing two empty files passes. Assert on output the slice
# actually emits before believing the diff.
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output"; exit 1; }
grep -q '^count=5$' "$work/native.txt" || {
  echo "FAIL the oracle did not report 5 arguments -- the harness, not the backend:"
  cat "$work/native.txt"; exit 1; }

if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  ParamCount; ParamStr as an expression (frozen temp); ArgStr into a"
  echo "..  managed string; an empty argument, one with a space, one of 200"
  echo "..  chars; the same index read twice; 200 reassignments of one dest"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# --- what native cannot be asked: out of range, and a 300-byte argument ------
vlong=$(printf 'x%.0s' $(seq 1 300))
"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/argv_oob_slice.pas" "$work/oob.wasm" > "$work/oobcov.txt" 2>&1
head -1 "$work/oobcov.txt"
wasm-validate "$work/oob.wasm"
node --no-warnings "$here/wasihost.js" "$work/oob.wasm" "$work/sandbox" \
    alpha '' 'two words' "$vlong" > "$work/oob.txt"
cat > "$work/oob.expected" <<'XEOF'
oob_expr=[]
oob_mgd=[] len=0
neg_mgd=[] len=0
long_len=300 xs=300
loop=50
done
XEOF
if diff -u "$work/oob.expected" "$work/oob.txt"; then
  echo "ok  an out-of-range or negative index yields the empty string, not the"
  echo "..  bytes that happen to follow the pointer vector; and a 300-byte"
  echo "..  argument survives whole, 50 times over, with the frame intact"
else
  echo "FAIL out-of-range or long-argument ParamStr misbehaved"; exit 1
fi

# check_all.sh treats this line as the sentinel that the script REACHED ITS END.
# A zero exit says only that nothing failed loudly; this says the last assertion
# actually ran.
echo "PASS check_argv"
