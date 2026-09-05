#!/bin/sh
# A managed `out` parameter on wasm32 — and, underneath it, a procedure body
# built in more than one CompileAST call.
#
# WHY THE TWO ARE THE SAME CHECK. FPC finalizes a managed `out` param on entry,
# and PXX emits that as an ordinary assignment (`s := ''`) rather than a new
# through-pointer emitter — which means it arrives as its OWN CompileAST call,
# BEFORE the declared body. A wasm function is one contiguous byte range, and
# this backend used to seal one per call, so the last write won and the clear
# was silently absent. Every register backend appends instead; wasm32 now
# resumes the slot (WasmBodyResume) and concatenates.
#
# THE FAILURE WAS SILENT AND THE MODULE VALIDATED. Both arms of the operand
# stack balance, every body reports as lowered, and `out s: AnsiString` simply
# handed the caller back its own previous value:
#
#     procedure Fill(out s: string); begin s := s + 'X'; s := s + 'Y'; end;
#     native [XY]        wasm32 [KEEPXY]
#
# So the native build is the oracle and a diff is the primary assertion. A
# structural grep would have to guess which of `$fp`, the clear, or the export
# went missing; the diff does not care.
#
# WHY EVERY ROUTINE PRINTS WHAT IT SAW ON ENTRY. The dropped chunk WAS the
# clear, so the caller's stale value surviving into the callee is the direct
# observable. Asserting only on the result would pass a callee that happened to
# overwrite the stale value anyway.
#
# THE THREE-CHUNK ROW IS NOT PADDING. `TwoOut(out a; out b)` builds its body in
# THREE calls, and it is the row that found the second half of this bug: the
# export was registered once per CHUNK, so the third ask hit the duplicate-
# export refusal and TWO managed out params would not compile on wasm32 AT ALL.
# A resume that only ever fired once passes every other row here.
#
# THE TWO NEGATIVE ROWS ARE THE OTHER DIRECTION, and no assertion about `out`
# can see them. `var` must NOT be cleared, and neither must an ordinal `out` —
# FPC clears only MANAGED ones. A fix that cleared every by-reference parameter
# would turn all four `out` rows green and both of these red.
#
# bug-a-wasm32-emits-a-separate-function-per-compileast-call-so-a-proc-built-in-
# two-calls-loses-a-body
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-outparam.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/outparam_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`. This compile FAILED
# outright before the fix — the duplicate-export refusal — so it is an
# assertion in its own right and not setup.
# ... and NOT bare either. Under `set -e` a failing compile exits the script
# here with the compiler's own diagnostic sitting unread in cov.txt, and the
# work dir is removed by the trap — so the check that most needs to explain
# itself printed nothing at all. Measured: running this against the pre-fix
# compiler produced an empty log and a bare exit 1.
if ! "$root/compiler/pascal26" --target=wasm32 \
      "$here/outparam_slice.pas" "$work/o.wasm" > "$work/cov.txt" 2>&1; then
  echo "FAIL the slice does not COMPILE for wasm32. Before the resume landed"
  echo "     this was the duplicate-export refusal on a body lowered once per"
  echo "     chunk — two managed out params could not be compiled at all:"
  sed 's/^/     /' "$work/cov.txt"
  exit 1
fi
head -1 "$work/cov.txt"
wasm-validate "$work/o.wasm"

# The invariant, asserted rather than assumed: after the resume there is
# exactly one seal per slot, so this census line must be ABSENT. Its presence
# means a body was overwritten and code is missing from a module that still
# validates.
if grep -q 'written more than once' "$work/cov.txt"; then
  echo "FAIL a slot was sealed twice without resuming — code is silently absent:"
  grep -A1 'written more than once' "$work/cov.txt"
  exit 1
fi
echo "ok  no slot was sealed twice: every chunk of a body resumed the one"
echo "..  before it instead of replacing it"

# The positive twin: a slice whose routines all refused would satisfy every
# assertion below vacuously.
if grep -qE '^    (OutStr|OutStrF|TwoOut|VarStr|OutOrd|OutDyn) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (OutStr|OutStrF|TwoOut|VarStr|OutOrd|OutDyn) ' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
const sp0 = inst.exports.sp.value;
try { inst.exports.main(); }
catch (e) { if (!(e instanceof h.HostExit)) throw e; }
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(h.text());
JS

node "$work/run.js" "$work/o.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  a managed out param cleared on entry, in a procedure and in a"
  echo "..  FUNCTION (whose earlier chunk leaves a result on the operand"
  echo "..  stack), a THREE-chunk body, an out dynamic array, and the two"
  echo "..  rows that must NOT be cleared"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# Named individually, so a failure says WHICH property went. The entry lines
# are the direct witness that the clear chunk survived; the after lines say the
# body chunk did too.
for want in '  OutStr entry=[]' 'OutStr  after=[XY]' \
            '  OutStrF entry=[]' 'OutStrF after=[X] r=42' \
            '  TwoOut entry=[][]' 'TwoOut  after=[A][B]' \
            '  OutDyn entry-len=0' 'OutDyn  after-len=1 [0]=7'; do
  if ! grep -qxF "$want" "$work/wasm.txt"; then
    echo "FAIL a managed out param was not cleared on entry, or its body chunk"
    echo "     was dropped: expected [$want]"
    exit 1
  fi
done
echo "ok  the entry clear AND the declared body are both present in every"
echo "..  multi-chunk routine — asserted on the entry value, which is what"
echo "..  the dropped chunk used to write"

for want in '  VarStr entry=[KEEP]' '  OutOrd entry=10'; do
  if ! grep -qxF "$want" "$work/wasm.txt"; then
    echo "FAIL the OTHER direction: a parameter that FPC does not finalize was"
    echo "     cleared anyway. Expected [$want]. Only MANAGED out params are"
    echo "     finalized on entry; var and ordinal out keep the caller's value."
    exit 1
  fi
done
echo "ok  var and ordinal-out keep the caller's value — a fix that cleared"
echo "..  every by-reference parameter would pass the rows above and fail here"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/outparam_slice.pas" "$work" o

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_outparam"
