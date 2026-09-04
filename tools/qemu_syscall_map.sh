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
  i386)    q=qemu-i386;    C3=3:read   C4=4:write   C5=5:open   CU=222 CB=4094 CR=20:getpid ;;
  arm32)   q=qemu-arm;     C3=3:read   C4=4:write   C5=5:open   CU=399 CB=4094 CR=20:getpid ;;
  aarch64) q=qemu-aarch64; C3=63:read  C4=64:write  C5=56:openat CU=460 CB=4094 CR=172:getpid ;;
  riscv32) q=qemu-riscv32; C3=63:read  C4=64:write  C5=56:openat CU=460 CB=4094 CR=172:getpid ;;
  xtensa)  q=qemu-xtensa;  C3=12:read  C4=13:write  C5=9:close  CU=399 CB=4094 CR=120:getpid ;;
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
# waits for a signal that never comes, and the first sweep sat on it forever
# having produced 27 rows. Inert arguments make a call harmless; they do not make
# it RETURN.
PROBE_TIMEOUT=${PROBE_TIMEOUT:-2}

# THE SUBJECT LINE IS FOUND BY DIFFING AGAINST A BASELINE, not by anchoring on
# exit_group -- and the three bugs that forced this rewrite are all the same
# shape: THE INSTRUMENT COULD NOT MEASURE ITS OWN LANDMARK. Found by franks-ab
# auditing the first arm32 map before building a header from it (three wrong rows
# out of ~52 examined; the other 314 were never in question because nobody had
# reason to look):
#
#   248  named mmap2, IS exit_group. Probing exit_group's own number leaves the
#        anchor sitting on the previous startup syscall. The landmark cannot
#        appear twice and be told apart.
#   29   named rt_sigreturn, IS pause. A BLOCKED call prints nothing at all --
#        qemu emits the line when the call returns -- so the anchor never moved
#        and the row kept whatever name happened to be there. The ?noreturn
#        MARKER was right and the NAME beside it had never been established.
#   2    absent, IS fork. fork returns twice, so the trace has TWO exit_group
#        lines and no single anchor, and the row vanished into "absent" -- which
#        this file's own header defines as nothing being at that number.
#
# So: run the probe once with a number known to be UNASSIGNED, keep that trace as
# the baseline, and for every N take the FIRST line that is not part of the
# common prefix. Return values are stripped before comparing, because a mapped
# address is not stable across runs. A number whose trace has no line past the
# prefix is `?noreturn` WITH NO NAME -- the honest answer, and the one the anchor
# version could not give.
trace_of() {
  timeout "$PROBE_TIMEOUT" "$q" -strace "$tmp/scn" "$1" 2>&1 | sed 's/^[0-9][0-9]* //' || true
}
# THE SUBJECT IS WHAT LIES BETWEEN THE SHARED PREFIX AND THE SHARED SUFFIX, and
# the SUFFIX half is not symmetry for its own sake. A prefix-only diff reports
# the first line past the common start, and for a syscall qemu executes while
# printing NOTHING that line is the program's own `exit_group(0)` -- so the
# number gets named exit_group. Measured on riscv32 259 (2026-09-04): a real
# call, no trace line, and the row read `259 exit_group`. It was caught only
# because 94 IS exit_group and the duplicate control fired; on an arch where the
# silent number came first there would be nothing to collide with.
#
# Bracketing between prefix and suffix makes the empty case VISIBLE instead of
# borrowing the next line: no middle at all means the call printed nothing, and
# `?silent` says exactly that. Return values are stripped before comparing
# because mapped addresses are not stable between runs; ARGUMENTS are not, which
# is what keeps `exit_group(2147483647)` (the probe calling exit_group itself)
# distinct from the baseline's `exit_group(0)`.
subject_of() {
  trace_of "$1" > "$tmp/t.txt"
  awk -v basef="$tmp/base.txt" '
    function key(l) { sub(/ = .*$/,"",l); return l }
    BEGIN { bn=0; while ((getline l < basef) > 0) b[++bn]=key(l) }
    { tn++; t[tn]=$0; k[tn]=key($0) }
    END {
      p=0; while (p < bn && p < tn && k[p+1] == b[p+1]) p++
      sfx=0; while (p+sfx < tn && bn-sfx > p && k[tn-sfx] == b[bn-sfx]) sfx++
      for (i = p+1; i <= tn-sfx; i++) print t[i]
    }
  ' "$tmp/t.txt"
}
name_of() {
  subject_of "$1" | head -1 | sed -n 's/^\([a-z_0-9]*\)(.*/\1/p'
}
line_of() {
  subject_of "$1"
}

# THE BASELINE NUMBER MUST LIE OUTSIDE EVERY SWEPT RANGE, and $CB is 4094 for
# that reason alone. A baseline's own diff against itself is empty, so it can
# never produce a row -- if the baseline sat inside the sweep, that number would
# be STRUCTURALLY INVISIBLE in the map and no control could see it, because the
# absence would be indistinguishable from a correct absence. $CU was the
# baseline until 2026-09-04 and is 399/460, both in range; it is now an ordinary
# in-range unassigned number, checked through the real path both before the
# sweep and against the finished map.
trace_of "$CB" > "$tmp/base.txt"
if [ ! -s "$tmp/base.txt" ]; then
  echo "qemu_syscall_map: the baseline trace for the unassigned number $CB is EMPTY." >&2
  echo "  Every row is derived from it, so a blank baseline would make the whole" >&2
  echo "  map read as 'first line of every trace'. Refusing." >&2
  exit 1
fi

fail=0
# THE CONTROL TABLE IS DATA AND IT HAS BEEN WRONG. Both of these fired for real:
# C5 said 57:openat for aarch64/riscv32 (openat is 56 there; 57 is close), and
# xtensa's row had no second unassigned number at all, because the edit that
# added one keyed on the CR spelling and xtensa's differs. The unset variable
# then probed with an EMPTY argument and reported the program's own exit --
# a confusing verdict for what was a missing table entry. Check the table's SHAPE before probing anything with it.
for cv in "$C3" "$C4" "$C5" "$CR"; do
  case "$cv" in
    [0-9]*:[a-z]*) : ;;
    *) echo "qemu_syscall_map: control entry '$cv' is not <number>:<name> for $arch" >&2; exit 2 ;;
  esac
done
case "$CU:$CB" in
  [0-9]*:[0-9]*) : ;;
  *) echo "qemu_syscall_map: $arch has no CU/CB pair (got '$CU'/'$CB')" >&2; exit 2 ;;
esac
[ "$CU" != "$CB" ] || { echo "qemu_syscall_map: CU must differ from the baseline CB" >&2; exit 2; }
check() {   # check <n>:<expected-name>
  n=${1%%:*}; want=${1##*:}; got=$(name_of "$n")
  if [ "$got" = "$want" ]; then echo "  control: $n -> $want  OK"
  else echo "  control: $n -> '$got', expected '$want'  FAIL"; fail=1; fi
}
echo "qemu_syscall_map: $arch via $q, controls first"
check "$C3"; check "$C4"; check "$C5"
a=$(name_of "${C3%%:*}"); b=$(name_of "${C4%%:*}"); c=$(name_of "${C5%%:*}")
if [ "$a" = "$b" ] || [ "$b" = "$c" ] || [ "$a" = "$c" ]; then
  echo "  control: the three control names are not distinct  FAIL"; fail=1
else
  echo "  control: three different numbers give three DISTINCT names  OK"
  echo "           (a constant shift within one family cannot pass this;"
  echo "            read+write alone could, being adjacent and same-family)"
fi
# THE ABSENCE CONTROL, and it has to run through the real path to mean anything.
# $CU is an unassigned number INSIDE the swept range, so the sweep must reach it
# and decide to emit nothing: qemu prints `Unknown syscall <n>`, which DIFFERS
# from the baseline's `Unknown syscall <CB>` and was being reported as a
# `?unnamed` row until 2026-09-04. While $CU was itself the baseline this
# control could not come out false at all -- its diff was empty by construction
# -- so it printed OK through the entire period the bug existed.
u2=$(subject_of "$CU")
case "$u2" in
  "Unknown syscall $CU"*) echo "  control: $CU unassigned, and via the real path  OK" ;;
  *) echo "  control: $CU gave '$u2', expected an Unknown-syscall line  FAIL"; fail=1 ;;
esac
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
  echo "# A '?unnamed' row is an ASSIGNED number that RETURNED and that qemu"
  echo "#   printed no name for -- its handler emitted only the return value. It"
  echo "#   is a real syscall and this tool cannot say which; look it up in the"
  echo "#   kernel table. arm32 90 (old_mmap) is the one instance at 0..460: its"
  echo "#   handler prints the struct argument, and the probe's argument is not a"
  echo "#   readable address, so the line comes out as bare ' = -1 errno=14'."
  echo "# A '?silent' row is an ASSIGNED number that RAN AND RETURNED and that"
  echo "#   qemu printed NO LINE AT ALL for. It is only distinguishable from an"
  echo "#   absent number because the subject is bracketed between the prefix AND"
  echo "#   the suffix the trace shares with the baseline; a prefix-only diff"
  echo "#   reported the probe'\''s own exit_group as this number'\''s name."
  echo "#   riscv32 259 is the measured case."
  echo "#   ABSENT, ?noreturn, ?unnamed and ?silent are FOUR different statements"
  echo "#   and only the first one means nothing is at that number."
  echo "# range: $lo..$hi   date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "# compiler: $(sha256sum "$here/../compiler/pascal26" 2>/dev/null | cut -c1-16)  commit: $(git -C "$here/.." rev-parse --short=12 HEAD 2>/dev/null)"
  n=$lo
  base_last=$(tail -1 "$tmp/base.txt")
  while [ "$n" -le "$hi" ]; do
    nm=$(name_of "$n")
    sub=$(subject_of "$n" | head -1)
    if [ -n "$nm" ]; then
      echo "$n $nm"
    elif [ "${sub#Unknown syscall}" != "$sub" ]; then
      : # qemu says the number is not in its table -- UNASSIGNED, no row.
        # This arm is why the baseline number cannot be the only absence
        # control: n == baseline produces an EMPTY diff and so can never
        # generate a row, whatever the code does -- which is why the baseline
        # $CB is kept OUTSIDE every swept range and $CU, the in-range
        # unassigned control, is a different number.
    elif [ -n "$sub" ]; then
      echo "$n ?unnamed"
    elif [ "$(trace_of "$n" | tail -1)" = "$base_last" ]; then
      # THE CALL RAN, RETURNED, AND PRINTED NOTHING -- the probe reached its own
      # exit and the trace ends exactly where the baseline's does. Distinguished
      # from an absent number only because the subject is bracketed by the
      # shared SUFFIX as well as the shared prefix; with a prefix-only diff this
      # row silently took the name of the program's exit_group. riscv32 259 is
      # the measured case, and it was caught only because 94 IS exit_group and
      # the duplicate control fired.
      echo "$n ?silent"
    elif [ "$(trace_of "$n" | wc -l)" -gt 0 ]; then
      # Printed nothing AND never reached the program's exit: it blocked, or it
      # does not return by design. NOT a line-count test any more -- a ?silent
      # trace is also exactly one line shorter than the baseline (the baseline's
      # own `Unknown syscall` line), so counting lines called every silent
      # syscall a non-returning one.
      echo "$n ?noreturn"
    fi
    n=$((n+1))
  done
} > "$out"
# ---------------------------------------------------------------------------
# OUTPUT-SIDE CONTROLS. Everything above checks INPUTS the tool chose to probe,
# and the first arm32 map passed all five of those while containing two misnamed
# rows. franks-ab found them with one line over the OUTPUT: no two numbers may
# name the same call, and the two duplicates WERE the two wrong rows. An
# invariant of the artefact is a class the input-side controls cannot cover, and
# it is free.
#
# THE FIRST TIME THIS GUARD FIRED IT WAS WRONG, and the way it was wrong is the
# reason check_map is a function with a self-test below rather than four lines
# at the end. It reported `syscall` twice and deleted a 460-number sweep. One
# `syscall` was arm32's real 113 (the indirect syscall); the other was the word
# in this file's own HEADER COMMENT, because the awk read every line and a
# comment has a second field too. The guard was reading a population -- all
# lines -- that was wider than the one its question was about -- rows. It also
# destroyed the evidence it was reporting on, so diagnosing it cost a re-sweep;
# a rejected map is now KEPT, under .rejected.
check_map() {   # check_map <file> <lo> <hi>; 0 = the map passes
  cm_f=$1; cm_lo=$2; cm_hi=$3; cm_rc=0
  cm_dups=$(awk '$1 ~ /^[0-9]+$/ && $2 !~ /^\?/ {print $2}' "$cm_f" | sort | uniq -d)
  if [ -n "$cm_dups" ]; then
    echo "qemu_syscall_map: TWO NUMBERS NAME THE SAME CALL -- the map is wrong:" >&2
    for d in $cm_dups; do
      echo "    $d at $(awk -v n="$d" '$1 ~ /^[0-9]+$/ && $2==n{printf "%s ",$1}' "$cm_f")" >&2
    done
    echo "  A duplicate means the extractor reported a line that was not the subject" >&2
    echo "  (see the trace_of/subject_of note above)." >&2
    cm_rc=1
  fi
  # ...and every name the arch's own control table asserts must actually be in
  # the map. This is the half that catches an ABSENCE -- a vanished row has no
  # name to collide with, which is exactly how fork went missing from the first
  # map.
  cm_missing=""
  for c in "$C3" "$C4" "$C5" "$CR"; do
    cn=${c%%:*}; nm=${c##*:}
    # Only for control numbers INSIDE the swept range -- otherwise a
    # deliberately narrow sweep fails on a row it was never asked to produce,
    # which is a guard firing on the wrong population rather than on a defect.
    [ "$cn" -ge "$cm_lo" ] && [ "$cn" -le "$cm_hi" ] || continue
    grep -q "^$cn $nm\$" "$cm_f" || cm_missing="$cm_missing $nm"
  done
  # ...and the in-range unassigned number must have produced NO row. This is the
  # same question the input-side control asks, asked of the ARTEFACT instead of
  # of one probe -- the only place a sweep-level regression can show up.
  if [ "$CU" -ge "$cm_lo" ] && [ "$CU" -le "$cm_hi" ] && grep -q "^$CU " "$cm_f"; then
    echo "qemu_syscall_map: $CU is unassigned and the map has a row for it:" >&2
    grep "^$CU " "$cm_f" >&2
    cm_rc=1
  fi
  if [ -n "$cm_missing" ]; then
    echo "qemu_syscall_map: control names missing from the map:$cm_missing" >&2
    echo "  They probed correctly one at a time, so the SWEEP dropped them --" >&2
    echo "  an absence has no name to collide with and the duplicate check cannot" >&2
    echo "  see it." >&2
    cm_rc=1
  fi
  return $cm_rc
}

# A POSITIVE CONTROL FOR THE CONTROLS, over synthetic maps, costing no qemu run.
# Both directions, because this guard has already failed in both: it must REJECT
# a map with a real duplicate and a map missing a control row, and it must ACCEPT
# a good one -- a check that says no to everything is as empty as one that never
# fires, and the header false-positive was exactly that.
cm_good="$tmp/selftest-good.map"
{
  echo "# syscall number -> name for $arch, and the word syscall is in this comment"
  for c in "$C3" "$C4" "$C5" "$CR"; do echo "${c%%:*} ${c##*:}"; done
  echo "$(( CB - 2 )) ?noreturn"
  echo "$(( CB - 1 )) ?noreturn"
} > "$cm_good"
cm_lo_t=$(awk '$1 ~ /^[0-9]+$/{print $1}' "$cm_good" | sort -n | head -1)
cm_hi_t=$(awk '$1 ~ /^[0-9]+$/{print $1}' "$cm_good" | sort -n | tail -1)
if check_map "$cm_good" "$cm_lo_t" "$cm_hi_t" 2>/dev/null; then
  echo "  control: the map checker ACCEPTS a good map (header comment included)  OK"
else
  echo "  control: the map checker rejected a GOOD map  FAIL"; fail=1
fi
cm_bad="$tmp/selftest-dup.map"
# A PURE duplicate: the good map plus one extra number carrying a name that is
# already in it. Nothing else about the map changes, so a rejection can only
# have come from the duplicate arm -- an injected fault that also breaks the
# coverage arm would leave the two indistinguishable and this control unaimed.
cp "$cm_good" "$cm_bad"
echo "9999 ${C3##*:}" >> "$cm_bad"
if check_map "$cm_bad" "$cm_lo_t" "$cm_hi_t" 2>/dev/null; then
  echo "  control: the map checker PASSED a duplicated name  FAIL"; fail=1
else
  echo "  control: the map checker rejects a duplicated name  OK"
fi
cm_gone="$tmp/selftest-missing.map"
grep -v "^${C3%%:*} " "$cm_good" > "$cm_gone"
if check_map "$cm_gone" "$cm_lo_t" "$cm_hi_t" 2>/dev/null; then
  echo "  control: the map checker PASSED a missing control row  FAIL"; fail=1
else
  echo "  control: the map checker rejects a missing control row  OK"
fi
[ "${fail:-0}" = 0 ] || { echo "qemu_syscall_map: a control failed; no map written." >&2; rm -f "$out"; exit 1; }

if check_map "$out" "$lo" "$hi"; then :; else
  mv -f "$out" "$out.rejected"
  echo "  The rejected map is kept at $out.rejected -- read it, do not re-sweep." >&2
  exit 1
fi
echo "  control: no two numbers name the same call  OK"
echo "  control: every control name is present in the map  OK"
echo "qemu_syscall_map: $(grep -c '^[0-9]' "$out") assigned numbers in $lo..$hi -> $out"
