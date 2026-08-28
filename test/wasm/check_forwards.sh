#!/bin/sh
# The FPC-seed hazard, checked in seconds instead of found in a gate.
#
# pxx resolves names across a whole unit; FPC — the bootstrap seed — resolves
# them in SOURCE ORDER. So a file can self-host perfectly and still break the
# seed build, and nothing in the per-fix loop looks, because
# `make compiler/pascal26` compiles with pxx. It has happened twice in
# ir_codegen_wasm32.inc, both times found only by `gate.sh quick`'s FPC canary,
# which runs once at the end of a phase.
#
# The lint itself is tools/forwardlint.py, on master, because it reads the whole
# compiler.pas include chain and is worth as much to every other lane as to
# this one. This file is just the wasm suite's caller. Its history is in that
# script's header, including why a per-file version had to be thrown away.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

python3 "$root/tools/forwardlint.py" "$root/compiler/compiler.pas"

echo "PASS check_forwards"
