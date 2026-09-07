#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# The `ok:` line must mean an artefact reached the disk.
#
# It did not, until 2026-09-07: `pascal26 src.pas /nonexistent-dir/out` printed
# `ok: ... [code=249624B ...]` and exited 0 having written nothing. The verb,
# the byte counts and the exit status are all computed from the in-memory image,
# so three signals agreed by construction -- one reading wearing three faces.
#
# BOTH DIRECTIONS ARE ASSERTED. A check that only proves the bad path refuses
# would pass if the compiler refused everything, which is a worse compiler and a
# green row.
set -u
PXX="${1:-compiler/pascal26}"
SRC="${2:-test/test_promoint_bitwise.pas}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rc=0

[ -x "$PXX" ] || { echo "FAIL $PXX is not executable — this check cannot mean anything"; exit 1; }
[ -f "$SRC" ] || { echo "FAIL $SRC is missing — this check cannot mean anything"; exit 1; }

# (1) MUST REFUSE: a path whose directory does not exist.
out=$("$PXX" "$SRC" "$W/no-such-dir/out" 2>&1); st=$?
if [ $st -eq 0 ]; then
  echo "FAIL the compiler exited 0 for an output path it could not write."
  echo "     Its own line: $(echo "$out" | tail -1)"
  echo "     The ok: line is computed from the in-memory image; if it is not"
  echo "     gated on the artefact, every harness that greps it is wrong three"
  echo "     ways at once (verb, byte counts, exit status)."
  rc=1
elif [ -e "$W/no-such-dir/out" ]; then
  echo "FAIL it refused, but the file exists — the refusal is about something else"; rc=1
else
  echo "ok   an unwritable output path is refused, rc=$st, and no file was left behind"
fi

# (2) MUST ACCEPT: the same source to a good path, and the artefact must be real.
out=$("$PXX" "$SRC" "$W/good" 2>&1); st=$?
if [ $st -ne 0 ]; then
  echo "FAIL a WRITABLE output path was refused (rc=$st) — the check rejects too much:"
  echo "$out" | sed 's/^/     /'
  rc=1
elif [ ! -s "$W/good" ]; then
  echo "FAIL it printed ok for a good path but the artefact is absent or empty"; rc=1
else
  echo "ok   a writable output path still succeeds, artefact $(wc -c < "$W/good") bytes"
fi

# (3) MUST ACCEPT: /dev/null. `-o /dev/null` asks "does this compile", and the
#     write DID succeed -- the kernel discarded it. Reading it back gives 0
#     bytes, which the existence test cannot tell from a failed write, so the
#     compiler names the sink explicitly and this row is what keeps that true.
out=$("$PXX" "$SRC" /dev/null 2>&1); st=$?
if [ $st -ne 0 ]; then
  echo "FAIL compiling to /dev/null was refused (rc=$st) — that idiom asks"
  echo "     whether the source compiles and must keep working:"
  echo "$out" | sed 's/^/     /'
  rc=1
else
  echo "ok   compiling to /dev/null still succeeds — a discard sink is not a failed write"
fi

[ $rc -eq 0 ] && echo "PASS ok_line_means_a_file" || echo "FAIL ok_line_means_a_file"
exit $rc
