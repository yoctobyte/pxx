#!/bin/sh
# The WASI PAL backend — the SEAM, not the syscalls.
#
# WHAT THIS STAGE IS. lib/rtl/platform/wasi/platform_backend.pas declares all
# 87 PAL entry points and implements none of them: every one returns
# PAL_ERR_UNSUPPORTED. That is not a placeholder for missing work, it is the
# ESP backend's own model — a POSIX-shaped program meets a clear error rather
# than a wrong answer — and it is worth landing on its own because of what it
# unblocks. Before this file existed, `uses SysUtils` did not compile for
# wasm32 AT ALL: posix is the compiled-in default PAL, it reaches the kernel
# through a per-architecture table of Linux syscall NUMBERS, and wasm32 fell
# into it and died at PARSE time on `undefined variable (SYS_openat)`.
#
# So the primary assertion is a diff of a SysUtils program against the native
# build, and its value is that every line of it was unreachable on this target
# for that one reason.
#
# WHY A THIRD BACKEND AND NOT AN ARM OF POSIX: wasm has no syscall instruction
# and no number space. A host call is an IMPORT, named by module and field,
# resolved at instantiation. There is nothing to add a {$ifdef CPU_WASM32}
# block to — the mechanism differs, not the constants.
#
# THE NEGATIVE BELOW IS A MECHANICAL EXPIRY, and it is the reason the backend
# needs no compiler change. Selection is `-Fu` on the unit search path:
# AddDefaultPasUnitDirs appends the posix default AFTER the user's -Fu dirs, so
# an explicit override wins. The check asserts that the default is still posix
# — i.e. that the same program still FAILS without the flag. The day wasm32
# selects the wasi directory by default (a compiler.pas change, a shared-file
# arm this branch has not taken), this goes red and the paragraph above has to
# be rewritten rather than quietly outliving its cause.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-pal.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

cp "$here/wasmhost.js" "$work/"

# --- the interface must stay in lockstep with the other backends ------------
# platform.pas calls 87 PalBackend* entry points and binds whichever backend is
# on the search path. posix and esp already agree exactly; a wasi backend that
# drifted would fail to compile with an error naming platform.pas rather than
# the missing declaration. Asserting parity puts the diagnosis where the cause
# is — and catches the other direction too, a routine declared here that no
# longer exists anywhere else.
ifaces() {
  awk '/^interface/,/^implementation/' "$1" \
    | tr '\n' ' ' | tr ';' '\n' \
    | grep -oE '(function|procedure) +PalBackend[A-Za-z0-9_]+' \
    | awk '{print $2}' | sort
}
ifaces "$root/lib/rtl/platform/posix/platform_backend.pas" > "$work/posix.i"
ifaces "$root/lib/rtl/platform/wasi/platform_backend.pas"  > "$work/wasi.i"
if ! diff -u "$work/posix.i" "$work/wasi.i" > "$work/iface.diff"; then
  echo "FAIL the wasi backend's PAL surface has drifted from posix's:"
  cat "$work/iface.diff"
  exit 1
fi
echo "ok  all $(wc -l < "$work/wasi.i") PAL entry points declared, same set as posix"

# --- the negative that motivates the file, and its expiry -------------------
if "$root/compiler/pascal26" --target=wasm32 "$here/pal_slice.pas" \
     "$work/nodir.wasm" > "$work/nodir.txt" 2>&1; then
  echo "ok  wasm32 now resolves the PAL without -Fu — the default backend"
  echo "    selection has landed. REWRITE this script's scope note: the"
  echo "    explicit-flag rationale above no longer describes the build."
  exit 1
fi
if ! grep -q 'SYS_openat' "$work/nodir.txt"; then
  echo "FAIL without -Fu the build fails for a DIFFERENT reason than the"
  echo "     posix default PAL — this negative no longer tests what it says:"
  head -4 "$work/nodir.txt"
  exit 1
fi
echo "ok  without -Fu the same program still dies on posix's SYS_openat —"
echo "..  the default PAL is unchanged and the override is what selects wasi"

# --- the primary assertion --------------------------------------------------
"$root/compiler/pascal26" -Fulib/rtl/platform/posix \
    "$here/pal_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/pal_slice.pas" "$work/p.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/p.wasm"

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

node "$work/run.js" "$work/p.wasm" > "$work/wasm.txt"
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  a SysUtils program matches the native build ($(wc -l < "$work/native.txt") lines)"
  echo "..  — every one of them unreachable on this target before the seam"
else
  echo "FAIL wasm diverges from native"; exit 1
fi
# The build still reports refusals (27 at the time of writing) and that is
# honest: those bodies exist and trap IF CALLED. The diff above is what proves
# the CALLED set is complete, which is a stronger statement than any grep over
# the refusal list, and it is why no such grep is here.

# --- the deliberate failure mode --------------------------------------------
# Everything behind the seam refuses. A program that actually opens a file must
# therefore meet a clean runtime error — not a trap, not a wrong answer, and
# not silence. That is the property the all-refusing stage is FOR, so it is
# asserted rather than assumed.
cat > "$work/io.pas" <<'EOF'
program IoRefuse;
var f: Text;
begin
  Assign(f, 'x.txt');
  Rewrite(f);
  writeln(f, 'hello');
  Close(f);
end.
EOF
"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$work/io.pas" "$work/io.wasm" > /dev/null 2>&1
# NOT the $sp-checking runner: this program TERMINATES rather than returning,
# and an exiting program does not unwind its frames — on any target. $sp being
# stale at proc_exit is correct, and the balance check is a statement about
# programs that return.
cat > "$work/runx.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
try { inst.exports.main(); }
catch (e) { if (!(e instanceof h.HostExit)) throw e; }
process.stdout.write(h.text());
JS
node "$work/runx.js" "$work/io.wasm" > "$work/io.txt" 2>&1
if ! grep -q 'Runtime error 38' "$work/io.txt"; then
  echo "FAIL opening a file does not refuse cleanly. An unimplemented PAL must"
  echo "     produce PAL_ERR_UNSUPPORTED (ENOSYS, 38), not a trap or a wrong"
  echo "     answer. Got:"
  cat "$work/io.txt"
  exit 1
fi
echo "ok  a program that opens a file refuses with runtime error 38 (ENOSYS)"
echo "..  — the deliberate failure mode, not a trap and not a wrong answer"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/pal_slice.pas" "$work" p \
   -Fulib/rtl/platform/wasi

echo "PASS check_pal"
