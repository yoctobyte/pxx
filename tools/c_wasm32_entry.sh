#!/bin/sh
# C ON wasm32 REACHES `main`, AND ITS EXIT CODE IS THE PROOF.
#
# bug-c-no-c-program-entry-stub-for-wasm32-so-no-c-program-can-target-it
#
# WHY EVERY EXPECTED VALUE HERE IS NONZERO. A wasm module that exports no
# `_start` is not rejected by anything: wasmtime instantiates it, runs nothing,
# and exits 0. `int main(void){return 0;}` also exits 0. So the ticket's own
# first acceptance criterion -- "int main(void){return 0;} exits 0 under
# wasmtime" -- is a guard that CANNOT FAIL, and it passed against a no-op entry
# stub during development. Measured, on a hand-written module exporting only
# `main`: rc=0.
#
# Every subject below therefore returns a value that a module doing nothing
# cannot produce, and rc=0 is treated as the FAILURE value throughout.
#
# THE THREE SUBJECTS ARE THREE CODE PATHS, not three flavours of the same one.
# WasmEmitCEntry reads main's declared arity, because wasm TYPE-CHECKS the call
# and `int main(void)` is a [] -> [i32] function: passing it two arguments is a
# module that fails validation. So arity 0 and arity 2 are separate arms, and a
# `void main` is a third (no result to exit with -- the wrapper supplies 0,
# which is why that row asserts a value it could only get by RUNNING).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/compiler/pascal26"
WORK=$(mktemp -d)

fail() { printf 'c_wasm32_entry: FAIL - %s\n' "$*" >&2; exit 1; }

[ -x "$COMPILER" ] || fail "no compiler at $COMPILER"

# The runtime. Absent is "cannot answer" (exit 2), this repo's convention for a
# missing oracle -- NOT a pass. wasmtime commonly lives in ~/.local/bin, which
# is on an interactive PATH but not on a non-login shell's.
WASMTIME=""
if command -v wasmtime >/dev/null 2>&1; then WASMTIME=wasmtime
elif [ -x "$HOME/.local/bin/wasmtime" ]; then WASMTIME="$HOME/.local/bin/wasmtime"
else
  echo "c_wasm32_entry: INCONCLUSIVE - no wasmtime; this is a host gap, not a result about wasm32" >&2
  exit 2
fi

# run <name> <source> <expected-rc> [args...]
run() {
  nm=$1; src=$2; want=$3; shift 3
  [ "$want" -ne 0 ] || fail "$nm: expected rc 0, which is also what a module with no _start returns -- see the header"
  rm -f "$WORK/$nm.wasm"
  # BRANCH on the compile. A comparison whose subject was never built cannot
  # fail, and an earlier run of this by hand read a STALE .wasm from a previous
  # build after the compile had errored -- rc=0 from a file that predated the
  # change under test.
  "$COMPILER" --target=wasm32 "$src" "$WORK/$nm.wasm" >"$WORK/$nm.log" 2>&1 \
    || { sed -n '1,3p' "$WORK/$nm.log" >&2; fail "$nm: did not compile"; }
  [ -f "$WORK/$nm.wasm" ] || fail "$nm: compiler reported success and wrote no module"
  # Capture-first, on its own line: `cmd; echo "rc=$?"` prints the truth and
  # EXITS 0, so a caller reading the status of the compound sees success
  # unconditionally. set -e must not see the nonzero either, hence `|| rc=$?`.
  rc=0
  "$WASMTIME" "$WORK/$nm.wasm" "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq "$want" ] \
    || fail "$nm: exit $rc, expected $want$([ "$rc" -eq 0 ] && printf ' (0 is what a module that never ran also gives)')"
  printf '  %-22s rc=%-3s ok\n' "$nm" "$rc"
}

cat > "$WORK/arity0.c" <<'EOF'
int main(void) { return 42; }
EOF
cat > "$WORK/argv.c" <<'EOF'
int main(int argc, char **argv)
{
	int n = 0;
	if (argv && argv[0] && argv[0][0]) n += 20;  /* argv[0] is a real string */
	return n + argc;                             /* 1 bare, 3 with two args */
}
EOF
echo "c_wasm32_entry: the C entry on wasm32"
run arity0            "$WORK/arity0.c" 42
run argv-bare         "$WORK/argv.c"   21
run argv-two-args     "$WORK/argv.c"   23 alpha beta

# STRUCTURAL: the export must be there and must be named `_start`. A wasm host
# starts a command module through that name and nothing else; `main` alone is
# what the module already had while running nothing.
rm -f "$WORK/x.wat"
"$COMPILER" --target=wasm32 "$WORK/arity0.c" "$WORK/x.wat" >/dev/null 2>&1 \
  || fail "the .wat form did not build"
grep -q '(export "_start"' "$WORK/x.wat" \
  || fail 'no (export "_start") in the module -- a host will run nothing and exit 0'
echo '  _start exported        ok'

# `void main` IS A THIRD ARM and it is asserted STRUCTURALLY, on purpose. It has
# no result to exit with, so the wrapper supplies 0 -- and 0 is this script's
# failure value, so an exit-code row for it would be the very guard-that-cannot-
# fail the header is about. What IS checkable is that the arm produces a module
# at all: get the result handling wrong for a procedure-shaped main and the body
# is ill-typed (a value left on the operand stack, or none where one is wanted)
# and the module does not build.
cat > "$WORK/voidmain.c" <<'EOF'
void main(void) { }
EOF
rm -f "$WORK/voidmain.wasm"
"$COMPILER" --target=wasm32 "$WORK/voidmain.c" "$WORK/voidmain.wasm" >"$WORK/voidmain.log" 2>&1   || { sed -n '1,3p' "$WORK/voidmain.log" >&2; fail "void main: did not compile"; }
rc=0
"$WASMTIME" "$WORK/voidmain.wasm" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "void main: exit $rc, expected 0 (the wrapper supplies it)"
echo '  void main builds+runs   ok (structural: 0 cannot discriminate here)'

# THE CONTROL FOR THE CONTROL: prove the 0-is-indistinguishable claim in this
# script rather than asserting it in a comment, so the reason every expectation
# above is nonzero stays checkable.
cat > "$WORK/nostart.wat" <<'EOF'
(module (func (export "main") (result i32) (i32.const 42)))
EOF
rc=0
"$WASMTIME" "$WORK/nostart.wat" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] \
  || fail "a module exporting only 'main' exited $rc, not 0 -- the premise that 0 cannot discriminate has changed, and these expectations should be revisited"
echo '  no-_start module gives rc=0 (why every row above is nonzero)'

echo "C-WASM32-ENTRY-COMPLETE"
