#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# census_at_exit.sh <binary> [args...]
#
# The EXACT allocation census of a pxx program at the moment it exits.
#
# WHAT IT ANSWERS: live-at-exit (allocs - frees), total allocs and frees and
# cumulative bytes, taken at the exit_group syscall. The binary must be built
# with -dPXX_ALLOC_CENSUS. gdb stops the process at exit_group and calls the
# runtime's own PXXCensusReport, found through the binary's .map. So nothing in
# the program under test changes, and the number is exact. The in-program
# census cannot give that number: it has no exit hook, so its last report fires
# on a geometric threshold and is only within ~12.5% (see
# tools/assert_no_leak.sh, which is the right tool for a bound in a test row).
#
# WHAT IT DOES NOT ANSWER: whether anything grows PER ITERATION. A handful live
# at exit is usually globals, caches and one-off setup, which is fine. Growth
# needs two runs of the same work at different counts, for example the main
# block wrapped and run N=1 against N=5, compared with this tool. Equal live
# counts mean a one-off; a difference proportional to N is a leak. Used that
# way in the 2026-09-25 leak sweep over docs/examples.
#
# Output: one line,
#   pxx-census: allocs=A frees=F live=L bytes=B reuse=... list=... bump=... arenas=...
# The program's own output is captured and discarded; its stdin is /dev/null.
# Exit 0 on a census line. 2 = not built with the census (no PXXCensusReport
# in <binary>.map). 3 = the program never reached exit_group (crash, signal,
# timeout), printed as NO-EXIT and never as numbers. 4 = no gdb.
#
# Arguments go through `gdb --args`, so any content survives, quotes and
# spaces included. Do NOT put them, or a redirect, on gdb's `run` line: `run
# ARGS` REPLACES the --args list, so a `run > /dev/null` silently drops argv.
# That is how the first draft of this tool measured a program that crashed on
# a NULL argv[1] as "0 allocations".
#
# And do NOT `set startup-with-shell off`. gdb stores --args as ONE string,
# shell-escaped, and without a shell older gdb splits that string on whitespace
# and never unescapes it. On borg, 2026-09-25, the devtest's argument
# `it's "a" b  c` (13 chars) measured live=6. 6 is the length of `it\'s\`, the
# first whitespace-split word of the escaped string (inferred from that count,
# not observed; borg's gdb was not inspected). gdb 17 is correct, so the same
# tool was green on plexus. With the
# shell (gdb's default) /bin/sh does the unescaping, on every gdb, and `exec`
# keeps the pid, so the exit_group catchpoint is the program's own. gdb
# starts it through $SHELL, which is pinned to /bin/sh: the escaping is POSIX.
set -uo pipefail

bin="${1:?usage: census_at_exit.sh <binary> [args...]}"
shift
command -v gdb >/dev/null 2>&1 || { echo "census_at_exit: gdb not found" >&2; exit 4; }
map="$bin.map"
addr=$(grep ' PXXCensusReport$' "$map" 2>/dev/null | cut -d' ' -f1)
if [ -z "$addr" ]; then
  echo "NO-CENSUS $bin (no PXXCensusReport in $map: build with -dPXX_ALLOC_CENSUS)"
  exit 2
fi

out=$(SHELL=/bin/sh timeout "${CENSUS_TIMEOUT:-300}" gdb -q -batch -nx \
        -ex 'set pagination off' \
        -ex 'catch syscall exit_group' \
        -ex 'run' \
        -ex "call ((void(*)(void))$addr)()" \
        --args "$bin" "$@" 2>&1 < /dev/null)
# The program's own output is captured in $out with gdb's and discarded; only
# the catchpoint banner and the LAST census line (the one the call above
# printed, after everything the program wrote) are read from it.
if ! printf '%s\n' "$out" | grep -q 'Catchpoint 1 (call to syscall exit_group)'; then
  why=$(printf '%s\n' "$out" | grep -m1 -iE 'received signal|exited|killed' || true)
  echo "NO-EXIT $bin ${why:-(no exit_group reached; timeout?)}"
  exit 3
fi
line=$(printf '%s\n' "$out" | grep '^pxx-census: allocs=' | tail -1)
[ -n "$line" ] || { echo "NO-EXIT $bin (reached exit_group but the report printed nothing)"; exit 3; }
echo "$line"
