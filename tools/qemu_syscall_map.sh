#!/bin/sh
# Map syscall NUMBER -> NAME for a cross target, by measurement rather than by
# copying a header.
#
# THE METHOD. One syscall per process, made as the LAST thing the program does,
# with every argument 2147483647 -- inert as a pointer (unmapped), as an fd (out
# of range) and as a pid (nonexistent AND positive, so it can never mean a
# process group). `qemu-<arch> -strace` names it. The line immediately before
# `exit_group(` is the subject; nothing is printed after the call, because a
# WriteLn would emit write(2) syscalls of its own and the extractor would have
# to guess which line was the subject.
#
# A many-syscalls-per-process scan is what this replaces and it is WRONG in a
# way that reads as right: qemu kills the process on a bogus call, the restart
# loses a number, and every row after it is off by one. That produced mmap2=79
# for xtensa where the true value is 80.
#
# WHAT THIS IS AN ORACLE ABOUT, and it is not the kernel. -strace reports what
# QEMU's own syscall table calls a number. That is a genuinely independent
# source -- it is not this repo's table read back -- but a divergence between
# qemu and a real kernel is INVISIBLE here and would look exactly like a correct
# number. The mitigation is population, not argument: every cross-target test in
# this tree runs under qemu, so these numbers are right for everything that
# currently exercises them. A first run on hardware is where they would be
# falsified. Do not write "measured" into a header without that sentence.
#
# THE CONTROLS, and why read/write alone are not enough. franks-ab's own
# verification of an earlier batch used 145+1 as a negative control and it
# ANSWERED THE SAME ERRNO, because 146 is writev and writev(-1,...) is EBADF
# too: an adjacent number in the same family is behaviourally indistinguishable.
# read=3 and write=4 have exactly that shape -- adjacent, same argument kinds --
# so a sweep shifted by a constant within a family would still pass them. This
# tool therefore asserts THREE CONSECUTIVE names, an UNASSIGNED number, and a
# call that RETURNS A VALUE rather than an errno:
#
#   three in a row   a constant shift breaks at least one of them
#   unassigned       proves the sweep can report ABSENCE, not just presence
#   returns a value  proves the probe reaches a real kernel path, and that a
#                    returning call is distinguishable from a failing one
#
# Every control must pass or the map is not written. A generator whose guard
# cannot fail produces a header nobody can check.
set -e
arch=$1
out=$2
lo=${3:-0}
hi=${4:-460}
if [ -z "$arch" ] || [ -z "$out" ]; then
  echo "usage: tools/qemu_syscall_map.sh <arch> <out-file> [lo] [hi]" >&2
  echo "  arch: i386 | arm32 | aarch64 | riscv32 | xtensa" >&2
  exit 2
fi
case $arch in
  i386)    q=qemu-i386;    C3=3:read   C4=4:write   C5=5:open   CU=399 CR=20:getpid ;;
  arm32)   q=qemu-arm;     C3=3:read   C4=4:write   C5=5:open   CU=399 CR=20:getpid ;;
  aarch64) q=qemu-aarch64; C3=63:read  C4=64:write  C5=57:openat CU=460 CR=172:getpid ;;
  riscv32) q=qemu-riscv32; C3=63:read  C4=64:write  C5=57:openat CU=460 CR=172:getpid ;;
  xtensa)  q=qemu-xtensa;  C3=12:read  C4=13:write  C5=9:close  CU=399 CR=120:getpid ;;
  *) echo "qemu_syscall_map: no control table for '$arch'." >&2
     echo "  REFUSING rather than sweeping without one: the controls are the only" >&2
     echo "  thing that separates this map from a guess. Add a row above, sourced" >&2
     echo "  from values this repo has already established independently." >&2
     exit 2 ;;
esac
command -v "$q" >/dev/null 2>&1 || { echo "qemu_syscall_map: $q not found" >&2; exit 2; }
here=$(dirname "$0")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/scn.pas" <<'PAS'
program scn;
uses sysutils;
var n: Integer; r: Int64;
begin
  n := StrToInt(ParamStr(1));
  r := __pxxrawsyscall(n, 2147483647, 2147483647, 2147483647, 2147483647, 2147483647, 2147483647);
  Halt(0);
end.
PAS
case $arch in
  xtensa) "$here/../compiler/pascal26" --target=xtensa --platform=posix --xtensa-soft-mulhigh --xtensa-long-calls "$tmp/scn.pas" "$tmp/scn" >/dev/null ;;
  *)      "$here/../compiler/pascal26" --target=$arch --platform=posix "$tmp/scn.pas" "$tmp/scn" >/dev/null ;;
esac
# name_of <n>  ->  the syscall name, or the empty string when unassigned
# EVERY PROBE IS TIMED OUT, and finding out why cost 11 minutes. Not every
# syscall fails on garbage arguments -- some BLOCK. arm32 #29 is pause(), which
# waits for a signal that never comes, and the sweep sat on it forever having
# produced 27 rows. Others in the same class: futex wait, wait4, nanosleep with a
# large timespec, read on a valid fd. `inert arguments` makes a call harmless; it
# does not make it RETURN.
#
# THE ABSENCE OF AN exit_group LINE HAS THREE READINGS, not one, and the label
# says so rather than picking the flattering one. The probe may have BLOCKED
# (arm32 282/283, bind and connect on a garbage address), or the call may not
# RETURN by design -- syscall 1 is exit, and 29/119/173 are sigreturn variants,
# none of which come back to the caller at all. A third reading, the emulator
# wedging, cannot be told from the first two here. So these are recorded as
# `<n> <name> ?noreturn`: an assigned number whose probe did not come back, for
# whichever of those reasons. What matters is that they are NOT silently dropped
# into "unassigned", which is what a bare failure would have looked like -- six
# real arm32 numbers, including exit itself.
PROBE_TIMEOUT=${PROBE_TIMEOUT:-3}
raw_of() {
  timeout "$PROBE_TIMEOUT" "$q" -strace "$tmp/scn" "$1" 2>&1 || true
}
name_of() {
  raw_of "$1" | grep -B1 'exit_group(' | head -1 \
    | sed -n 's/^[0-9][0-9]* \([a-z_0-9]*\)(.*/\1/p'
}
# The name a BLOCKED probe was on: no exit_group line, so take the last syscall
# line instead. Empty for a genuinely unassigned number.
blocked_name_of() {
  raw_of "$1" | sed -n 's/^[0-9][0-9]* \([a-z_0-9]*\)(.*/\1/p' | tail -1
}
line_of() {
  raw_of "$1" | grep -B1 'exit_group(' | head -1
}
fail=0
check() {   # check <n>:<expected-name>
  n=${1%%:*}; want=${1##*:}; got=$(name_of "$n")
  if [ "$got" = "$want" ]; then echo "  control: $n -> $want  OK"
  else echo "  control: $n -> '$got', expected '$want'  FAIL"; fail=1; fi
}
echo "qemu_syscall_map: $arch via $q, controls first"
check "$C3"; check "$C4"; check "$C5"
a=$(name_of "${C3%%:*}"); b=$(name_of "${C4%%:*}"); c=$(name_of "${C5%%:*}")
if [ "$a" = "$b" ] || [ "$b" = "$c" ] || [ "$a" = "$c" ]; then
  echo "  control: the three consecutive names are not distinct  FAIL"; fail=1
else
  echo "  control: three consecutive numbers give three DISTINCT names  OK"
  echo "           (a constant shift within one family cannot pass this;"
  echo "            read+write alone could, being adjacent and same-family)"
fi
u=$(name_of "$CU")
if [ -z "$u" ]; then echo "  control: $CU is unassigned, sweep reports ABSENCE  OK"
else echo "  control: $CU named '$u', expected unassigned  FAIL"; fail=1; fi
rn=${CR%%:*}; rw=${CR##*:}; rl=$(line_of "$rn")
if [ "$(name_of "$rn")" = "$rw" ] && ! printf '%s' "$rl" | grep -q 'errno='; then
  echo "  control: $rn -> $rw RETURNS a value, not an errno  OK"
else
  echo "  control: $rn -> $rw did not return a value: $rl  FAIL"; fail=1
fi
if [ "$fail" != "0" ]; then
  echo "qemu_syscall_map: CONTROLS FAILED -- no map written." >&2
  exit 1
fi
{
  echo "# syscall number -> name for $arch, measured under $q -strace."
  echo "# Generated by tools/qemu_syscall_map.sh; read its header before using this."
  echo "# THIS IS AN ORACLE ABOUT QEMU, not about a kernel on real hardware. Every"
  echo "# cross-target test in this tree runs under qemu, so these are right for the"
  echo "# whole population that exercises them; a first run on hardware is where they"
  echo "# would be falsified. Do not copy a value out of here under the word"
  echo "# 'measured' without carrying that sentence with it."
  echo "# A '?noreturn' row is an ASSIGNED number whose probe did not come back:"
  echo "#   it blocked, or the call does not return by design (exit, sigreturn)."
  echo "#   Not the same as an absent row, which means nothing is at that number."
  echo "# range: $lo..$hi   date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "# compiler: $(sha256sum "$here/../compiler/pascal26" 2>/dev/null | cut -c1-16)  commit: $(git -C "$here/.." rev-parse --short=12 HEAD 2>/dev/null)"
  n=$lo
  while [ "$n" -le "$hi" ]; do
    nm=$(name_of "$n")
    if [ -n "$nm" ]; then
      echo "$n $nm"
    else
      bn=$(blocked_name_of "$n")
      # A name with no exit_group means the probe was still inside that call
      # when the timeout fired. Anything else (including the startup mmap2) is
      # not evidence of an assigned number.
      case "$bn" in
        ''|mmap2|mmap|brk|exit_group) : ;;
        *) echo "$n $bn ?noreturn" ;;
      esac
    fi
    n=$((n+1))
  done
} > "$out"
echo "qemu_syscall_map: $(grep -c '^[0-9]' "$out") assigned numbers in $lo..$hi -> $out"
