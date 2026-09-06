#!/bin/sh
# The WASI PAL backend — the SEAM, not the syscalls.
#
# WHAT THIS CHECKS: the SEAM, not the syscalls. check_wasi.sh owns the file
# operations; this one owns "a program that pulls the PAL compiles and runs".
#
# Those are worth separating because the seam is what actually unblocked the
# target. Before lib/rtl/platform/wasi existed, `uses SysUtils` did not compile
# for wasm32 AT ALL: posix is the compiled-in default PAL, it reaches the
# kernel through a per-architecture table of Linux syscall NUMBERS, and wasm32
# fell into it and died at PARSE time on `undefined variable (SYS_openat)`.
# So the primary assertion is a diff of a SysUtils program against the native
# build, and its value is that every line of it was unreachable on this target
# for that one reason — before any PAL entry point was implemented, and still
# true of the ones that are not.
#
# WHY A THIRD BACKEND AND NOT AN ARM OF POSIX: wasm has no syscall instruction
# and no number space. A host call is an IMPORT, named by module and field,
# resolved at instantiation. There is nothing to add a {$ifdef CPU_WASM32}
# block to — the mechanism differs, not the constants.
#
# THE EXPIRY FIRED — 2026-09-05. This section used to assert the opposite of
# what it asserts now, and the change is recorded rather than overwritten
# because the two states are one commit apart and the old one is still what a
# dozen-plus Makefile rows assume.
#
# It used to say: selection is `-Fu` on the unit search path, the default is
# posix, so the same program must still FAIL without the flag — and the day
# wasm32 selected wasi by default this would go red and the paragraph would
# have to be rewritten. That day came. The check did exactly what it was built
# to do: it exited 1 saying REWRITE MY SCOPE NOTE, which is why this paragraph
# exists instead of a stale one nobody noticed.
#
# WHAT IS TRUE NOW, and all three are asserted below rather than described:
#   1. `--target=wasm32` with no -Fu at all compiles and runs.
#   2. It is BYTE-IDENTICAL to an explicit `-Fulib/rtl/platform/wasi` build.
#      Compiling is not evidence that it selected wasi; identity is.
#   3. An explicit `-Fulib/rtl/platform/posix` STILL WINS and still dies on
#      `undefined variable (SYS_openat)`.
#
# (3) is not a leftover — it is a live trap and the reason to keep testing it.
# AddDefaultPasUnitDirs appends the target's own PAL AFTER the user's -Fu dirs,
# deliberately, so an explicit override beats the default. A Makefile row that
# hardcodes `-Fulib/rtl/platform/posix` is therefore correct natively and wrong
# cross, and it fails with a PARSE error naming a Linux syscall constant, which
# reads like a compiler bug rather than a flag that is doing what it was asked.
# That misreading has already cost one session a false report.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-pal.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

# --- the interface must stay in lockstep with the other backends ------------
# platform.pas calls 87 PalBackend* entry points and binds whichever backend is
# on the search path. posix and esp already agree exactly; a wasi backend that
# drifted would fail to compile with an error naming platform.pas rather than
# the missing declaration. Asserting parity puts the diagnosis where the cause
# is — and catches the other direction too, a routine declared here that no
# longer exists anywhere else.
# AIMED BEFORE ANYTHING IS READ. Every -Fu here is "$root"-relative and used to
# be relative to the CWD, which made this file answer a different question from
# any directory but the repo root: the compiler ignores a -Fu naming a
# directory that does not exist, so the override silently evaporated, the
# default wasi PAL built cleanly, and assertion (3) reported the override as
# BROKEN. The same slip made (2) vacuous rather than red -- it compared the
# default build against the default build and could not fail, and the PAL
# surface row below printed "all 0 PAL entry points declared, same set as
# posix", because an empty set does equal an empty set.
#
# So: the trees must EXIST before any row is allowed to mean anything.
for d in "$root/lib/rtl/platform/posix" "$root/lib/rtl/platform/wasi"; do
  [ -d "$d" ] || { echo "FAIL $d is not a directory, so every -Fu in this file"
                   echo "     names nothing and the compiler ignores it"
                   echo "     silently. No row here can mean anything until"
                   echo "     that is true."
                   exit 1; }
done

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
n_pal=$(wc -l < "$work/wasi.i")
# A set equals itself when both are empty, so the diff above passes loudest
# exactly when the extraction broke. The count is the population check.
[ "$n_pal" -gt 50 ] || { echo "FAIL only $n_pal PAL entry points were extracted, so the"
                         echo "     set-equality above compared two (near-)empty sets and"
                         echo "     could not have failed. The awk/grep pipeline or the"
                         echo "     backend's interface section moved."
                         exit 1; }
echo "ok  all $n_pal PAL entry points declared, same set as posix"

# --- selection: the default, its identity, and the override -----------------
# (1) no -Fu at all. This is what every ordinary build does, so it is also the
#     compile whose output the primary assertion below runs.
if ! "$root/compiler/pascal26" --target=wasm32 \
      "$here/pal_slice.pas" "$work/p.wasm" > "$work/cov.txt" 2>&1; then
  echo "FAIL a PAL-using program no longer compiles for wasm32 with no -Fu."
  echo "     The default backend selection is what makes the target usable;"
  echo "     without it every `uses SysUtils` program needs an explicit flag:"
  sed 's/^/     /' "$work/cov.txt"
  exit 1
fi
head -1 "$work/cov.txt"

# (2) COMPILING IS NOT EVIDENCE IT PICKED WASI. It could have found some third
#     thing, or a stub, and still produced a module. Identity with the explicit
#     build is the assertion; anything else is an inference.
"$root/compiler/pascal26" --target=wasm32 -Fu"$root"/lib/rtl/platform/wasi \
    "$here/pal_slice.pas" "$work/p_explicit.wasm" > "$work/explicit.txt" 2>&1
if ! cmp -s "$work/p.wasm" "$work/p_explicit.wasm"; then
  echo "FAIL the default build is not the same module as an explicit"
  echo "     -Fu"$root"/lib/rtl/platform/wasi build, so the default resolved to"
  echo "     something else. Sizes: $(wc -c < "$work/p.wasm") vs $(wc -c < "$work/p_explicit.wasm")"
  exit 1
fi
echo "ok  the default IS wasi — byte-identical to an explicit -Fu build, not"
echo "..  merely a build that happened to succeed"

# (3) The override still wins, and this is the live trap: a Makefile row that
#     hardcodes the posix PAL is correct natively and wrong cross.
if "$root/compiler/pascal26" --target=wasm32 -Fu"$root"/lib/rtl/platform/posix \
     "$here/pal_slice.pas" "$work/px.wasm" > "$work/px.txt" 2>&1; then
  echo "FAIL an explicit -Fu"$root"/lib/rtl/platform/posix no longer overrides the"
  echo "     default on wasm32. AddDefaultPasUnitDirs appends the target PAL"
  echo "     AFTER the user's dirs precisely so an override wins; if that"
  echo "     stopped being true, every -Fu in the tree means something else."
  exit 1
fi
if ! grep -q 'SYS_openat' "$work/px.txt"; then
  echo "FAIL the posix override fails for a DIFFERENT reason than reaching for"
  echo "     a Linux syscall number — this no longer tests what it says:"
  head -4 "$work/px.txt"
  exit 1
fi
echo "ok  an explicit posix -Fu still overrides and still dies on SYS_openat"
echo "..  — the trap a hardcoded platform flag sets for a cross build, and it"
echo "..  reads like a compiler bug rather than a flag doing as it was told"

# --- the primary assertion --------------------------------------------------
"$root/compiler/pascal26" -Fu"$root"/lib/rtl/platform/posix \
    "$here/pal_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"
wasm-validate "$work/p.wasm"

# Run against node's own WASI, not wasmhost.js. The moment anything calls a PAL
# entry point the module imports the WASI surface, and a shim that provided
# only what the backend happened to need would agree with the backend by
# construction. wasihost.js checks $sp for a normal return, same as the other
# slices.
mkdir -p "$work/sandbox"
node --no-warnings "$here/wasihost.js" "$work/p.wasm" "$work/sandbox" \
    > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
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
"$root/compiler/pascal26" --target=wasm32 -Fu"$root"/lib/rtl/platform/wasi \
    "$work/io.pas" "$work/io.wasm" > /dev/null 2>&1
# Run with NO preopened directory, which is what makes this a refusal test
# rather than a filesystem test: a WASI program given no grant can open
# nothing, whatever the backend does. wasihost.js skips the $sp check when the
# program exits non-zero, which this one does.
#
# `|| true` here does not hide anything: the assertion is the grep below, and a
# node crash or a module that failed to instantiate leaves io.txt without the
# expected line, so the check still fails — with node's own error printed. The
# non-zero exit being tolerated is the POINT of the case, not an inconvenience
# being suppressed.
node --no-warnings "$here/wasihost.js" "$work/io.wasm" "" > "$work/io.txt" 2>&1 || true
if ! grep -q 'Runtime error 2' "$work/io.txt"; then
  echo "FAIL opening a file with NO preopened directory does not refuse"
  echo "     cleanly. A program that was granted nothing must meet a plain"
  echo "     ENOENT (2) — the path does not exist in the namespace it was"
  echo "     given — not a trap and not a wrong answer. Got:"
  cat "$work/io.txt"
  exit 1
fi
echo "ok  with no preopened directory, opening a file refuses with runtime"
echo "..  error 2 (ENOENT) — the capability model's failure, not a trap"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/pal_slice.pas" "$work" p \
   -Fu"$root"/lib/rtl/platform/wasi

echo "PASS check_pal"
