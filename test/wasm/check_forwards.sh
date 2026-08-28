#!/bin/sh
# The FPC-seed hazard, checked in a second instead of found in a gate.
#
# pxx accepts a call to a routine defined LATER in the same include; FPC — the
# bootstrap seed — does not. So a file can self-host perfectly and still break
# the seed build, and NOTHING in the per-fix loop looks, because
# `make compiler/pascal26` compiles with pxx. It has happened twice in this
# file, both times found by `gate.sh quick`'s FPC canary, which runs once at
# the end of a phase — so the window each time was a whole phase of commits.
#
# The forward block carried a written-down rule ("every routine the dispatchers
# dispatch to belongs here"), and the second break walked straight past it:
# WasmEmitIndArgs is not a dispatch target, it is called by a BUILTIN lowering
# that happens to sit above the machinery it shares. A rule that is slightly
# wrong is worse than no rule, because it is read as complete.
#
# So this is a check rather than a rule. It reads the same file FPC does and
# asks FPC's question — is every call to a routine of this file preceded by
# either its definition or a forward — in about a second.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

python3 "$here/forwardlint.py" \
    "$root/compiler/ir_codegen_wasm32.inc" \
    "$root/compiler/wasmenc.inc" \
    "$root/compiler/asmtext_wasm.inc"

echo "PASS check_forwards"
