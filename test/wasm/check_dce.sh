#!/bin/sh
# --dce on wasm32: the module must shrink AND still be right.
#
# Two assertions, and neither is sufficient alone. That is the whole design:
#
#   - IDENTICAL STDOUT against the --no-dce build. Not the exit status. A
#     sibling defect on riscv32 (bug-a-dce-breaks-every-c-program-on-every-
#     cross-target) prints NOTHING and exits 0, so a harness asserting only rc
#     calls a dropped program body a pass.
#   - THE MODULE SHRANK. Equal output is also exactly what a pass that dropped
#     nothing produces, and on this target "dropped nothing" was the DEFAULT
#     outcome for as long as the backend exported every routine -- every
#     function was a root, so a correctly wired pass walked the whole module
#     and reported a clean zero. That failure mode is not hypothetical here, it
#     is the state this check was written to leave behind.
#
# The fixture reaches its override through a BASE-CLASS reference, so the only
# thing keeping that body alive is the element segment. See dce_slice.pas.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-dce.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

command -v node >/dev/null 2>&1 || { echo "SKIP check_dce (no node)"; exit 0; }
command -v wasm-validate >/dev/null 2>&1 || { echo "SKIP check_dce (no wasm-validate)"; exit 0; }

"$root/compiler/pascal26" --target=wasm32 --no-dce "$here/dce_slice.pas" "$work/off.wasm" > /dev/null
"$root/compiler/pascal26" --target=wasm32 --dce    "$here/dce_slice.pas" "$work/on.wasm"  > /dev/null

wasm-validate "$work/off.wasm"
wasm-validate "$work/on.wasm"
echo "ok  both modules validate"

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
let code = 0;
try { inst.exports.main(); } catch (e) { if (e instanceof h.HostExit) code = e.code|0; else throw e; }
process.stdout.write(h.text(1));
process.exit(code);
JS

for leg in off on; do
  if node "$work/run.js" "$work/$leg.wasm" > "$work/$leg.txt" 2>"$work/$leg.err"; then :; else
    echo "FAIL the --$leg module exited nonzero under wasm:"
    cat "$work/$leg.txt" "$work/$leg.err"; exit 1
  fi
done

# The oracle has to have RUN. Two empty files compare equal, and a build that
# trapped before printing would produce exactly that.
[ -s "$work/off.txt" ] || { echo "FAIL the --no-dce build produced NO output, so the diff"; echo "     below had nothing to compare and would pass on two empty files"; exit 1; }
grep -qx "area=49" "$work/off.txt" || { echo "FAIL the --no-dce oracle did not print area=49, so this check"; echo "     would be measuring a broken reference:"; cat "$work/off.txt"; exit 1; }
echo "ok  the --no-dce oracle ran and printed the right answer"

if diff -u "$work/off.txt" "$work/on.txt"; then
  echo "ok  --dce output is identical: the virtual override survived, so the"
  echo "..  element segment rooted a body no direct call names"
else
  echo "FAIL --dce changed the program's output"; exit 1
fi

# The shrink assertion. Without it the row above passes for a pass that did
# nothing, which is the outcome this target produced by construction until the
# blanket per-routine export stopped being a root.
soff=$(wc -c < "$work/off.wasm")
son=$(wc -c < "$work/on.wasm")
[ "$son" -lt "$soff" ] || {
  echo "FAIL --dce did not shrink the module ($soff -> $son bytes)."
  echo "     Identical output alone does not show the pass ran: a pass that"
  echo "     drops nothing also produces identical output. Check whether"
  echo "     something is rooting every function again -- the export table is"
  echo "     the one that did it before."; exit 1; }
echo "ok  module shrank: $soff -> $son bytes"

# And the dead body must actually be gone by NAME, not merely by byte count --
# a module could shrink for an unrelated reason. NeverReached is called by
# nothing and address-taken by nothing.
if wasm-objdump -x -j Export "$work/off.wasm" | grep -q 'NeverReached'; then
  echo "ok  NeverReached is present without --dce (the control: it CAN be seen)"
else
  echo "FAIL NeverReached is absent even without --dce, so its absence below"
  echo "     proves nothing -- this check cannot tell a dropped body from a"
  echo "     body that was never emitted under this name"; exit 1
fi
if wasm-objdump -x -j Export "$work/on.wasm" | grep -q 'NeverReached'; then
  echo "FAIL NeverReached survived --dce; nothing in the program reaches it"; exit 1
fi
echo "ok  NeverReached was dropped, and was visible before it was"

# THE .wat FORM IS THE SECOND SPELLING OF THIS MODULE AND IT HAD NO ROW HERE.
# Everything above builds a .wasm. The text writer is a separate emitter over
# the same tables, so it needs the same --dce filters -- and for one day it did
# not have them: `--dce` built a .wasm off a source and REFUSED the .wat, with
# an error naming the export table. A check that exercises one output form
# cannot see a defect in the other, however thorough it is about the first.
if command -v wat2wasm >/dev/null 2>&1; then
  "$root/compiler/pascal26" --target=wasm32 --no-dce "$here/dce_slice.pas" "$work/off.wat" > /dev/null \
    || { echo "FAIL the --no-dce .wat did not build, so the --dce row below"; \
         echo "     would not be measuring --dce"; exit 1; }
  "$root/compiler/pascal26" --target=wasm32 --dce "$here/dce_slice.pas" "$work/on.wat" > "$work/wat.err" 2>&1 \
    || { echo "FAIL --dce could not write the .wat form (it writes the .wasm):"; \
         cat "$work/wat.err"; exit 1; }
  echo "ok  both .wat forms build"

  # And it must still be an ORACLE, not merely a file: assembling it back has
  # to produce the module the binary writer produced.
  #
  # WHAT IS COMPARED AND WHAT IS NOT, both measured rather than assumed. pxx
  # writes FIXED 5-byte LEB size placeholders and wat2wasm writes minimal ones,
  # so byte offsets differ everywhere and the CODE section's payload differs
  # too -- one padded length prefix per function body, 0x3fc5 against 0x3de3 on
  # this fixture, ~4 bytes x ~120 bodies. That is an encoding width, not a
  # disagreement about the program.
  #
  # This row's first draft compared every section size and was RED on arrival
  # for exactly that reason, after a hand check that had matched -- because the
  # hand check read the first twelve lines of the header dump and Code is the
  # thirteenth. The instrument caught the claim its author had already made.
  #
  # So: every section EXCEPT Code must agree byte-for-byte in payload size, and
  # Code is held to the thing that actually matters -- the same functions, with
  # the same names, exported in the same order.
  wat2wasm "$work/on.wat" -o "$work/on_fromwat.wasm" \
    || { echo "FAIL the --dce .wat does not assemble"; exit 1; }
  for leg in on on_fromwat; do
    # The section name is RIGHT-ALIGNED in this dump, so it carries leading
    # spaces and an anchored `^Code` matches nothing -- which silently left
    # Code in the comparison and made this row red for the encoding-width
    # reason the comment above says it must not be red for.
    wasm-objdump -h "$work/$leg.wasm" | grep -v 'Code start=' \
      | sed -n 's/^ *\([A-Za-z]*\) .*(\(size=0x[0-9a-f]*\)).*/\1 \2/p' > "$work/sz.$leg"
    wasm-objdump -x -j Export "$work/$leg.wasm" \
      | sed -n 's/.*-> "\(.*\)"/\1/p' > "$work/exp.$leg"
  done
  [ -s "$work/sz.on" ] || { echo "FAIL no section sizes were extracted, so the diff below"; \
                            echo "     would pass on two empty files"; exit 1; }
  [ -s "$work/exp.on" ] || { echo "FAIL no exports were extracted, so the export diff"; \
                             echo "     below would pass on two empty files"; exit 1; }
  if diff -u "$work/sz.on" "$work/sz.on_fromwat" && diff -u "$work/exp.on" "$work/exp.on_fromwat"; then
    echo "ok  the --dce .wat reassembles to the same module: $(wc -l < "$work/exp.on") exports, every non-Code section byte-identical"
  else
    echo "FAIL the .wat and .wasm forms of one --dce module disagree"; exit 1
  fi
else
  echo "SKIP the .wat oracle rows (no wat2wasm)"
fi

echo "PASS check_dce"
