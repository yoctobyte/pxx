#!/bin/sh
# An interface value read THROUGH AN ADDRESS on wasm32 — a record field, a
# pointer deref.
#
# WHY THIS SHAPE HAD TO BE DECIDED IN THE IR, not here. An interface is spelled
# `tyRecord` throughout the type system, so a record-typed IR_LOAD_MEM reached
# every backend and each had to guess what one means. The two right answers are
# opposite:
#
#   * a real aggregate — its VALUE is its ADDRESS, so yield the address;
#   * an interface — the field HOLDS the pointer, so the value is what a load
#     reads.
#
# wasm32 was the only target that said anything: it refused outright with
# `load through a pointer of type record`. The tempting local fix — widening
# that arm to `or (tk = tyRecord)` — compiles, self-hosts, and silently yields
# `@r.I` where `r.I` was wanted; both are i32 and the module validates. frankA
# measured that and reverted it. The lowering now tags an interface-valued read
# `Ord(tyPointer)`, one arm along from the dynamic-array handle read that
# already did exactly this, so no backend carries the distinction.
#
# WHY `<> nil` IS NOT THE ASSERTION, and this is the part worth keeping. A
# skipped load yields the field's ADDRESS, which is ALSO non-nil — so the
# obvious check passes on the exact defect it is supposed to catch. Every row
# below is chosen so the wrong answer differs from the right one:
#
#   ptr-nonnil  the ticket's own repro, kept for continuity — it is the weakest
#               row here and is not load-bearing
#   roundtrip   assigns the field back into an interface and CALLS through it;
#               an address yields garbage or the wrong number, never 42
#   via-ptr     the same read one indirection along, through `p^.I`
#   neighbour   the adjacent Integer field, which a wrong-width load smears
#   direct      calling straight off the field read with no intermediate
#
# THE NATIVE BUILD IS THE ORACLE for all of them, so no expected value is
# written down twice and the check cannot drift from what the language means.
#
# `test_assign_lvalue_shapes_ok.pas` is run too, by the ticket's own request:
# it is a whole-file exercise of "none of these may be refused" and was the ONLY
# wasm32-broken body outside the NilPy PAL group.
#
# bug-a-wasm32-refuses-a-load-of-an-interface-valued-record-field
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-intf.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

cp "$here/wasmhost.js" "$work/"

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

# Two sources, same treatment. The second is the ticket's named guard.
for pair in "intf_slice:$here/intf_slice.pas" \
            "lvalue_shapes:$root/test/test_assign_lvalue_shapes_ok.pas"; do
  tag=${pair%%:*}
  src=${pair#*:}

  "$root/compiler/pascal26" "$src" "$work/$tag.native" >/dev/null
  "$work/$tag.native" > "$work/$tag.native.txt"

  # NOT piped and NOT bare: under `set -e` a failing compile exits here with
  # the compiler's own diagnostic unread in the log, and the trap then deletes
  # it — so the check that most needs to explain itself prints nothing. This
  # compile is itself an assertion: before the fix, intf_slice REFUSED.
  if ! "$root/compiler/pascal26" --target=wasm32 \
        "$src" "$work/$tag.wasm" > "$work/$tag.cov.txt" 2>&1; then
    echo "FAIL $tag does not COMPILE for wasm32:"
    sed 's/^/     /' "$work/$tag.cov.txt"
    exit 1
  fi
  head -1 "$work/$tag.cov.txt"
  wasm-validate "$work/$tag.wasm"

  # A REFUSED body does not fail the compile — it becomes `unreachable` and the
  # module still validates and still runs. That is exactly how this bug
  # presented, so the refusal census is an assertion and not decoration.
  if grep -q 'emitted as `unreachable`' "$work/$tag.cov.txt"; then
    echo "FAIL $tag has a body this backend could not lower:"
    grep -A3 'emitted as `unreachable`' "$work/$tag.cov.txt"
    exit 1
  fi

  node "$work/run.js" "$work/$tag.wasm" > "$work/$tag.wasm.txt"
  [ -s "$work/$tag.native.txt" ] || { echo "FAIL $tag: the oracle produced NO output, so the"; echo "     comparison would have passed on two empty files"; exit 1; }
  if diff -u "$work/$tag.native.txt" "$work/$tag.wasm.txt"; then
    echo "ok  $tag matches the native build ($(wc -l < "$work/$tag.native.txt") lines)"
  else
    echo "FAIL $tag diverges from native"; exit 1
  fi
done

# Named individually, so a failure says WHICH property went rather than "the
# diff moved". The round trip is the one that separates a real pointer from the
# field's address; `ptr-nonnil` cannot, and is not trusted to.
for want in 'roundtrip=42' 'via-ptr=42' 'direct=42' 'neighbour=7'; do
  if ! grep -qxF "$want" "$work/intf_slice.wasm.txt"; then
    echo "FAIL an interface read through an address did not yield the INSTANCE"
    echo "     pointer: expected [$want]. A skipped load hands back the FIELD'S"
    echo "     ADDRESS, which is non-nil and validates — so this row, not a nil"
    echo "     check, is what sees it."
    exit 1
  fi
done
echo "ok  the value read is the instance pointer, not the field's address —"
echo "..  proven by CALLING through it (42), through a record pointer, and"
echo "..  directly off the field, with the adjacent field intact"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/intf_slice.pas" "$work" intf_slice

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_intf"
