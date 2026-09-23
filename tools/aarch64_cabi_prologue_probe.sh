#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Does pxx's aarch64 C-function PROLOGUE read its parameters from the same
# registers a real aarch64 compiler puts them in?
#
#   tools/aarch64_cabi_prologue_probe.sh ['<C signature>' ...]
#
# WHY THIS EXISTS RATHER THAN A LINK TEST. The honest way to settle a calling
# convention is to have the OTHER toolchain call you -- a pxx-compiled callee
# linked against a gcc-compiled caller, which is what test/c_abi_mixed_link_*.c
# does on x86-64. That needs an object writer, and aarch64 has none; getting one
# is the ticket this probe was written under
# (feature-a-object-output-for-arm32-and-aarch64), whose stated gate is the ABI
# question this probe answers.
#
# So it takes the external opinion WITHOUT linking: clang compiles the same
# signature for aarch64 and we compare WHERE EACH SIDE EXPECTS EACH ARGUMENT.
# That is a genuine second toolchain, not pxx agreeing with itself -- a
# pxx-caller/pxx-callee pair uses one convention on both ends and passes under
# either answer, which is precisely the trap this ticket's premise sat in for
# weeks: AAPCS and positional COINCIDE for every all-integer and every
# all-pointer signature, which is the shape of every libc callback, so the whole
# existing corpus is green under both and can falsify neither.
#
# THE DISCRIMINATOR IS AN INTERLEAVED SIGNATURE. AAPCS64 counts the integer
# bank (x0..x7) and the FP bank (d0..d7) INDEPENDENTLY; pxx's internal
# convention is positional (arg i in x[i]). For f(int,double,int,double):
#
#     AAPCS      a->w0  b->d0  c->w1  d->d1     <- banks counted apart
#     positional a->w0  b->x1  c->w2  d->x3     <- one sequence
#
# Every all-int or all-double signature gives the SAME answer under both and is
# a free pass. Do not read one as evidence.
#
# HOW IT FINDS f, since a pxx executable carries no symbol table: it compiles
# the program twice, once with f and once without, and diffs the disassembly.
# The block present only in the first build is f. Locating it by a marker
# constant does not work -- pxx puts large immediates in a literal pool, so the
# marker appears in the pool and not in the code that loads it.
#
# Exit 0 if every signature agrees with clang, 1 on a real disagreement, and
# 2 when the INSTRUMENT failed and nothing could be compared.
#
# THE THREE EXITS ARE THE POINT AND THE THIRD ONE WAS MISSING UNTIL 2026-09-22.
# Before then a BROKEN row -- one where a side produced NO register list at all
# -- set rc=1, so the run ended by printing `verdict: DISAGREEMENT` having
# compared ZERO signatures, three lines under its own correct prose saying
# `this is an INSTRUMENT failure, not a result`. It diagnosed itself and then
# discarded the diagnosis. Found on borg 2026-09-22 by a peer reading the row's
# reason text: `clang extracted: []`, `pxx extracted: []`, `0 signature(s)
# agree with clang, 0 skipped`, `verdict: DISAGREEMENT`. That is CLAUDE.md's
# comparison-whose-inputs-were-never-proven-to-exist, and it does not merely
# fail to fail -- it fails in the WRONG DIRECTION, manufacturing a verdict
# about pxx out of an environment failure. It was one of the rows holding the
# `full` tier red on the only breadth host we had.
#
# AND THE ATTRIBUTION IS BY SIDE, not by row, because the two sides mean
# opposite things. An empty list from CLANG is the oracle failing: we learn
# nothing, exit 2. An empty list from PXX with clang's list present is a real
# finding about our own prologue, exit 1. The old code could not tell them
# apart, so a genuine pxx defect and a broken box both printed BROKEN.
#
# NOT exit 0. Matching the CLANG-ABSENT arm above (the `command -v "$CLANG"`
# guard) was the obvious move and it
# is wrong: an ABSENT clang is a declared host limitation, while a clang that
# is present and yields nothing is an UNDIAGNOSED condition, and exiting 0
# would launder it into a pass. See done/bug-t-tstate-launders-skip-into-pass.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PXX="${PXX_PROBE_CC:-$REPO_ROOT/compiler/pascal26}"
CLANG="${CLANG:-clang}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -x "$PXX" ] || { echo "probe: compiler not built ($PXX)" >&2; exit 2; }
command -v "$CLANG" >/dev/null || { echo "probe: clang absent; aarch64 C-ABI prologue NOT verified" >&2; exit 0; }
# THE SECOND TOOL WAS NEVER GATED, AND ITS ABSENCE FAILS INTO THE WRONG
# CHANNEL. `pxx_regs` disassembles with `llvm-objdump-21` -- a HARD-CODED LLVM
# major version -- and until 2026-09-22 nothing checked it existed. On a host
# with an older toolchain that command is simply missing, its output is empty,
# and the PXX side of every comparison comes back with no register list. That
# is indistinguishable, downstream, from pxx emitting a broken prologue: it
# reaches the BROKEN branch and gets attributed to the compiler.
#
# The probe gated the oracle it had thought about and not the one it had
# forgotten, and the ungated one is the one whose failure blames us. Borg's
# rows show BOTH sides empty, which is only reachable when the pxx side is
# empty too -- the stack-passed SKIP requires clang empty AND pxx non-empty --
# so a missing objdump is a live candidate for that host and this gate is how
# it will say so instead of being read as a compiler defect.
#
# Accept an unsuffixed `llvm-objdump` as a fallback rather than demanding the
# exact major: the disassembly this parses is stable across versions, and
# pinning a major by NAME is what made the dependency invisible.
# AND THE GATE MUST PROVE THE TOOL RUNS, NOT THAT THE NAME IS NON-EMPTY. The
# first version of this guard checked `[ -n "$OBJDUMP" ]`, which an explicit
# `LLVM_OBJDUMP=/nonexistent/llvm-objdump` satisfies -- so the guard passed,
# the disassembly produced nothing, and the run printed
# `verdict: DISAGREEMENT -- 5 pxx-side broken`. That is the EXACT defect this
# gate was added to prevent, reproduced by the gate itself within minutes of
# writing it, because a name standing in for the thing it names is not a check.
# Run it and require success.
#
# ^^ AND `--version` IS STILL AN EXIT CODE STANDING IN FOR A CAPABILITY, which
# is this same lesson one level further in. Measured 2026-09-23 across two
# hosts: llvm-objdump-18 and -20 on borg, and llvm-objdump-21 on plexus, ALL
# pass `--version` and ALL decode exactly nothing on `native/pxx-aarch64` --
# `error: The end of the file was unexpectedly encountered`, zero mnemonics.
# A gate that cannot come out false for the failure it was written for is not
# a gate.
#
# THE DISCRIMINATOR IS NOT THE VERSION AND NOT SECTIONLESSNESS, and both of
# those were live diagnoses until the crossing control was run. Two seats
# measured honestly and disagreed because each called its own file "pxx's
# aarch64 image" and neither reported its VINTAGE: one tested a committed
# August binary under -18/-20, the other a fresh HEAD build under -21. Crossed,
# -21 fails on the old artefact on the host where it succeeds on the new one.
# What actually decides it is `memsz` >> `filesz` on the segment carrying the
# code. llvm-objdump synthesises a `PT_LOAD#N` pseudo-section spanning MEMSZ
# and then reads past the end of a shorter file:
#
#   native/pxx-aarch64 (old emitter): ONE rwx LOAD, filesz 0x462c60, memsz 0x8690f0b
#   fresh build at HEAD:              R E LOAD,     filesz == memsz == 0x10000
#                                     RW  LOAD carries the bss, away from the code
#
# The modern emitter separates text from bss, so the text segment is fully
# backed by the file and decodes at every version tested. `-b binary` is not
# an escape -- llvm-objdump has no such option -- but it was never the reason.
#
# SO GATE ON DECODED MNEMONICS FROM A REAL PXX AARCH64 IMAGE. Not on the name,
# not on `--version`, and not on non-empty OUTPUT either: disassembly starts at
# the load address, so the ELF and program headers decode first and yield ~118
# lines of `<unknown>`/`udf` before any code. "Produced output" is satisfied by
# a run that found no instructions at all.
#
# AND ACCEPT GNU objdump WHERE IT CAN DO THE TARGET. Measured the same day:
# plexus has GNU binutils 2.46, whose objdump is SINGLE-TARGET x86-64
# (`objdump --info | grep -ci aarch64` = 0) and has llvm-objdump-21; borg has
# binutils 2.42, which DOES list elf64-littleaarch64, and has no llvm-objdump
# under either probed spelling. Neither host can use the other's tool, and the
# newer host is the weaker one -- so "upgrade binutils" is the wrong reflex and
# a candidate list cannot express this at all. A capability probe can.
# The two flavours need different flags: GNU objdump has no `--triple=`.
disas() {  # $1 = tool, $2 = flavour, $3 = file
  case "$2" in
    llvm) "$1" -d --triple=aarch64 "$3" 2>/dev/null ;;
    gnu)  "$1" -d "$3" 2>/dev/null ;;
  esac
}
# Real aarch64 mnemonics, not `<unknown>` and not `udf` (which is what a
# misaligned or past-EOF decode yields while still looking like output).
count_mnemonics() {
  grep -cE '[[:space:]](stp|ldp|ldr|str|mov|movz|movk|add|sub|ret|bl|cbz|cmp|adrp)([[:space:]]|$)' || true
}
# A canary the candidate must actually disassemble: built by THIS pxx, for this
# target, so the capability question is asked about the artefact class the probe
# will really hand it.
printf 'program canary;\nbegin\n  WriteLn(1);\nend.\n' > "$WORK/canary.pas"
if ! "$PXX" --target=aarch64 --system-libs=c "$WORK/canary.pas" "$WORK/canary.a64" >/dev/null 2>&1; then
  echo "probe: pxx cannot build an aarch64 canary; NOT verified" >&2; exit 2
fi
objdump_decodes() {  # $1 = tool, $2 = flavour
  command -v "$1" >/dev/null 2>&1 || return 1
  [ "$(disas "$1" "$2" "$WORK/canary.a64" | count_mnemonics)" -ge 10 ]
}
OBJDUMP=""; OBJDUMP_KIND=""
TRIED=""
try_cand() {  # $1 = tool, $2 = flavour
  TRIED="$TRIED $1"
  if objdump_decodes "$1" "$2"; then OBJDUMP="$1"; OBJDUMP_KIND="$2"; return 0; fi
  return 1
}
if [ -n "${LLVM_OBJDUMP:-}" ]; then
  # An explicit override still has to prove it decodes; naming a tool is not
  # evidence it can read this target, which is the whole point above.
  try_cand "$LLVM_OBJDUMP" llvm || try_cand "$LLVM_OBJDUMP" gnu || {
    echo "probe: LLVM_OBJDUMP=$LLVM_OBJDUMP does not DECODE a pxx aarch64 image" >&2
    echo "       (it may run and still find no instructions); refusing to guess." >&2
    echo "       INSTRUMENT failure -- this is NOT a statement about pxx." >&2
    exit 2; }
else
  # GNU objdump first where it is multi-target: it is the one tool that is
  # already present on every box here, and where it works it needs nothing
  # installed. Then llvm-objdump, VERSION-GLOBBED so this does not break again
  # at the next major -- a baked-in number is what made the dependency
  # invisible in the first place, and 21 was already wrong for borg.
  if objdump --info 2>/dev/null | grep -qi aarch64; then
    try_cand objdump gnu || true
  fi
  if [ -z "$OBJDUMP" ]; then
    # Scan PATH by hand rather than with `compgen -c`: compgen leans on bash's
    # completion machinery, and this has to behave the same on a host I cannot
    # test. Highest major first, then the unsuffixed name.
    llvm_cands() {
      local d
      local IFS=:
      for d in $PATH; do
        [ -d "$d" ] || continue
        for f in "$d"/llvm-objdump-[0-9]*; do
          [ -x "$f" ] && basename "$f"
        done
      done | sort -u -t- -k3,3nr
      echo llvm-objdump
    }
    for cand in $(llvm_cands); do
      try_cand "$cand" llvm && break
    done
  fi
fi
[ -n "$OBJDUMP" ] || {
  echo "probe: no disassembler can DECODE a pxx aarch64 image." >&2
  echo "       Tried:$TRIED" >&2
  echo "       A tool that runs is not a tool that decodes: every llvm-objdump" >&2
  echo "       tested passes --version and returns zero instructions on an image" >&2
  echo "       whose code segment has memsz >> filesz. GNU objdump is accepted" >&2
  echo "       when \`objdump --info\` lists aarch64 (binutils 2.42 does; the" >&2
  echo "       single-target 2.46 build on plexus does not)." >&2
  echo "       This is an INSTRUMENT failure and is NOT a statement about pxx." >&2
  echo "       Set LLVM_OBJDUMP=<path>, or install a multi-target binutils." >&2
  exit 2; }
"$CLANG" -print-targets 2>/dev/null | grep -q '^ *aarch64 ' || {
  echo "probe: this clang cannot target aarch64; NOT verified" >&2; exit 0; }

# The oracle's identity is part of every verdict this prints. Two boxes running
# different clangs can legitimately disagree at the margins, and a row quoted
# into a ticket without it cannot be told apart from a pxx regression -- the
# (TIER, HOST) confounder one layer over, where the axis is the TOOLCHAIN.
CLANG_VER="$("$CLANG" --version 2>/dev/null | head -1)"
echo "oracle: $CLANG_VER"

# Default population. Each entry is a full parameter list; the body just has to
# touch every parameter so none is optimised away at -O0.
SIGS=(
  "int a, double b, int c, double d"
  "double b, int a, double d, int c"
  "int a, int b, double c, double d"
  "float a, int b, float c, int d"
  "int a, double b, float c, int d, double e"
  "int a1, int a2, int a3, int a4, int a5, int a6, int a7, int a8, int a9, double b1"
  "double b1, double b2, double b3, double b4, double b5, double b6, double b7, double b8, double b9, int a1"
)
[ $# -gt 0 ] && SIGS=("$@")

# The stores a prologue makes, in order, as a register list. For clang this is
# the leading run of `str <reg>, [sp...]`; for pxx it is the `str <reg>, [x8]`
# that follows each `add x8, x29, x9`.
# Note both helpers end in `|| true`: `diff` exits 1 when the files DIFFER,
# which is the case this probe exists to produce, and under `set -o pipefail`
# that aborted the whole script before it printed a single row. An instrument
# that dies on its own success looks exactly like one that found nothing.
clang_regs() {
  # Instructions are TAB-indented in clang's asm output, so the leading
  # whitespace is stripped before matching -- anchoring on ^[a-z] silently
  # matched nothing and reported an empty register list for every signature.
  "$CLANG" --target=aarch64-linux-gnu -O0 -S "$1" -o - 2>/dev/null \
    | awk '/^f:/{inf=1;next}
           inf{ line=$0; sub(/^[ \t]+/,"",line); if (line=="") next;
                n=split(line,F," ");
                if (F[1]=="str" || F[1]=="stur") { r=F[2]; sub(",","",r); print r }
                else if (F[1]=="ldr"||F[1]=="ldur"||F[1]=="ret") exit }' || true
}

# PXX_SIDE_BLAMEABLE says whether an empty pxx list is OUR fault. It is set per
# call and read by the loop, because the same empty list has two causes that a
# register comparison cannot tell apart:
#
#   pxx failed to COMPILE          -> a real result about pxx      (blameable)
#   pxx compiled, disassembly empty -> the disassembler did nothing (instrument)
#
# Until 2026-09-22 neither was checked: both compiles sent their output to
# /dev/null and their exit status was discarded, and the disassembly was never
# asserted non-empty -- so a host without a working llvm-objdump produced an
# empty pxx list for every signature and the run blamed the compiler. That is
# this file's own "assert the precondition, not just the comparison", and the
# precondition here is that the two artefacts the comparison reads EXIST.
# COMMUNICATED THROUGH A FILE, NOT A VARIABLE, AND THAT IS NOT STYLE. The
# caller reads this helper as `p=$(pxx_regs ...)`, and a command substitution
# runs in a SUBSHELL -- so a global assigned in here is discarded on return and
# the caller silently keeps the previous value. The first version of this flag
# was a plain variable and it never propagated: the wrong-tool control still
# printed `5 pxx-side broken`, i.e. the exact false accusation the flag exists
# to prevent, with nothing erroring. A file in $WORK crosses the subshell.
pxx_blameable() { [ "$(cat "$WORK/blameable" 2>/dev/null || echo 1)" = 1 ]; }
pxx_regs() {
  local withf="$1" nof="$2" a="$WORK/a.a64" b="$WORK/b.a64"
  echo 1 > "$WORK/blameable"
  if ! "$PXX" --target=aarch64 --system-libs=c "$withf" "$a" >/dev/null 2>&1 \
     || ! "$PXX" --target=aarch64 --system-libs=c "$nof" "$b" >/dev/null 2>&1; then
    # A compile failure IS a result about pxx: leave it blameable and return
    # nothing. The caller reports it as a pxx-side BROKEN row.
    return 0
  fi
  disas "$OBJDUMP" "$OBJDUMP_KIND" "$a" | sed 's/^[^\t]*\t[^\t]*\t//' > "$WORK/a.txt"
  disas "$OBJDUMP" "$OBJDUMP_KIND" "$b" | sed 's/^[^\t]*\t[^\t]*\t//' > "$WORK/b.txt"
  # Both objects compiled, so a disassembly with no lines at all is the TOOL
  # failing, not pxx. Checked on both files: one empty is enough, since the
  # comparison is a diff of the two.
  if [ ! -s "$WORK/a.txt" ] || [ ! -s "$WORK/b.txt" ]; then
    echo 0 > "$WORK/blameable"
    return 0
  fi
  # `x8, x29, x9` is the slot-address setup both arms emit; the store right
  # after it names the register the argument arrived in, which is the one thing
  # the two conventions disagree about.
  { diff "$WORK/b.txt" "$WORK/a.txt" || true; } | grep '^>' | sed 's/^> //' \
    | awk '/^x8, x29, x9$/{want=1;next} want{r=$1; sub(",","",r); print r; want=0}' || true
}

rc=0
skipped=0
agreed=0
oracle_broke=0
pxx_broke=0
differed=0
for sig in "${SIGS[@]}"; do
  names=$(printf '%s' "$sig" | tr ',' '\n' | awk '{print $NF}' | tr -d '*')
  sum=$(printf '%s' "$names" | awk '{printf " + (double)%s", $1}')
  # Call arguments are LITERALS, not the parameter names -- those are not in
  # scope in main, and using them made every pxx compile fail while the probe
  # reported an empty register list that compared equal to clang's.
  #
  # Each literal ENCODES ITS OWN POSITION (11, 22, 33, ...) and none is 0, 1 or
  # a repeat. A swapped pair is only visible if every argument is distinct and
  # identifiable; passing anything repeated makes a transposition invisible and
  # the row passes for the wrong reason. The values do not affect the prologue
  # this probe reads, but they keep the program a valid runtime test for anyone
  # who later links it against a real caller.
  args=$(printf '%s' "$sig" | tr ',' '\n' | awk '{printf "%s%d", (NR>1?",":""), NR*11}')
  cat > "$WORK/withf.c" <<EOF
int printf(const char *fmt, ...);
double f($sig){ return 0.0$sum; }
int main(void){ printf("%.1f\n", f($args)); return 0; }
EOF
  # The SAME translation unit minus f, so the diff isolates exactly f's code.
  # It keeps the printf call so the two builds differ by f and nothing else --
  # dropping it too would leave the whole stdio path in the diff as well.
  cat > "$WORK/nof.c" <<EOF
int printf(const char *fmt, ...);
int main(void){ printf("%.1f\n", 0.0); return 0; }
EOF
  # clang needs a definition it will not inline away; -O0 already guarantees that.
  cat > "$WORK/clang.c" <<EOF
double f($sig){ return 0.0$sum; }
EOF
  c=$(clang_regs "$WORK/clang.c" | tr '\n' ' ')
  p=$(pxx_regs "$WORK/withf.c" "$WORK/nof.c" | tr '\n' ' ')
  # EMPTY IS NOT AGREEMENT, and without this line it reads as the loudest
  # possible agreement: two failed extractions compare equal and every row
  # prints AGREE with a blank register list. Both of this probe's first-run
  # bugs produced exactly that, so the check is not hypothetical -- it is the
  # failure that actually happened, caught only because a nonzero exit arrived
  # with no rows at all. A register list is also never shorter than the
  # argument count.
  #
  # AND NOTE WHICH DIRECTION THIS GUARD COVERS, because the 2026-09-22 defect
  # was the OTHER one. This line stops an empty extraction reading as AGREE.
  # Nothing stopped it reading as DISAGREEMENT, so the same empty extraction
  # that is correctly refused here went on to produce a confident verdict
  # about pxx at the end of the run. One insight, two directions, guarded in
  # one -- which is why the verdict below is now derived from counters that
  # name the SIDE that failed.
  nargs=$(printf '%s' "$names" | grep -c .)
  # STACK-PASSED ARGUMENTS ARE OUT OF SCOPE, and the probe decides that from
  # CLANG'S OWN OUTPUT rather than from an argument count of its own. Once a
  # bank overflows, clang's prologue opens by LOADING the incoming stack block,
  # so the leading run of stores this probe reads does not exist and the
  # register comparison has nothing to compare. Saying so is not the same as
  # passing: where the arguments live on the stack is a question about
  # OFFSETS, and answering it needs a different instrument than this one.
  # Deriving the skip from clang's shape and not from "more than 8 of a bank"
  # keeps it from being a filter that restates the thing being tested.
  if [ -z "$c" ] && [ -n "$p" ]; then
    printf '  SKIP    %-72s  (stack-passed: clang spills no registers here,\n' "$sig"
    printf '          %-72s   so this register comparison does not apply --\n' ""
    printf '          %-72s   offsets need their own probe)\n' ""
    skipped=$((skipped + 1))
    continue
  fi
  if [ -z "$c" ] || [ -z "$p" ]; then
    printf '  BROKEN  %s\n            clang extracted: [%s]\n            pxx   extracted: [%s]\n' \
      "$sig" "$c" "$p"
    if [ -z "$c" ]; then
      # The ORACLE produced nothing. We learn nothing about pxx from this row,
      # so it must not reach the disagreement channel.
      printf '            THE ORACLE produced no register list; this is an INSTRUMENT failure, not a result\n'
      oracle_broke=$((oracle_broke + 1))
    elif ! pxx_blameable; then
      # pxx compiled both objects and the DISASSEMBLER returned nothing. The
      # list is empty for a reason that has nothing to do with our prologue.
      printf '            the DISASSEMBLER (%s) produced no output for objects that compiled;\n' "$OBJDUMP"
      printf '            this is an INSTRUMENT failure, not a result about pxx\n'
      oracle_broke=$((oracle_broke + 1))
    else
      # clang extracted a list and pxx did not, and pxx's own compile is the
      # reason: that IS a finding about our prologue, and it is the half the
      # old single BROKEN label hid.
      printf '            PXX produced no register list while clang did; this is a RESULT about pxx\n'
      pxx_broke=$((pxx_broke + 1))
    fi
    continue
  fi
  if [ "$(printf '%s' "$c" | wc -w)" -lt "$nargs" ] || [ "$(printf '%s' "$p" | wc -w)" -lt "$nargs" ]; then
    printf '  BROKEN  %s\n            fewer stores than arguments (%d): clang [%s] pxx [%s]\n' \
      "$sig" "$nargs" "$c" "$p"
    if [ "$(printf '%s' "$c" | wc -w)" -lt "$nargs" ]; then
      printf '            THE ORACLE is short; instrument failure, not a result\n'
      oracle_broke=$((oracle_broke + 1))
    else
      printf '            PXX is short while clang is not; this is a RESULT about pxx\n'
      pxx_broke=$((pxx_broke + 1))
    fi
    continue
  fi
  # Compare exactly the first nargs stores. The parameter spill is by
  # construction the FIRST thing either prologue does, and everything after it
  # belongs to the body -- f's own arithmetic temporaries land through the same
  # `add x8, x29, x9` shape, so an untruncated list carries trailing registers
  # that mean nothing here. Truncating is safe only because the length check
  # above already refused a list SHORTER than the argument count; on its own it
  # would silently compare two empty prefixes.
  c=$(printf '%s' "$c" | awk -v n="$nargs" '{for(i=1;i<=n;i++) printf "%s ", $i}')
  p=$(printf '%s' "$p" | awk -v n="$nargs" '{for(i=1;i<=n;i++) printf "%s ", $i}')
  if [ "$c" = "$p" ]; then
    printf '  AGREE   %-72s  %s\n' "$sig" "$p"
    agreed=$((agreed + 1))
  else
    # The clang VERSION goes on the DIFFER row, not only in the header. A row
    # gets quoted into a ticket or a message and travels alone, and a different
    # clang can legitimately place arguments differently at the margins -- so a
    # quoted DIFFER with no version is unreadable, and reads as a pxx
    # regression. Record the method beside the number, never the number alone.
    printf '  DIFFER  %s\n            clang: %s   (%s)\n            pxx:   %s\n' \
      "$sig" "$c" "$CLANG_VER" "$p"
    printf '            read this against the local clang BEFORE reading it as a pxx change\n'
    differed=$((differed + 1))
  fi
done

echo "aarch64 C-ABI prologue: $agreed signature(s) agree with clang, $skipped skipped (stack-passed)"
# THE VERDICT IS DERIVED FROM THE COUNTERS, never from a single rc flag that
# three unrelated branches were free to set. A verdict must not be able to say
# DISAGREEMENT when nothing was compared.
if [ $differed -eq 0 ] && [ $pxx_broke -eq 0 ] && [ $oracle_broke -eq 0 ]; then
  if [ $agreed -eq 0 ]; then
    # Zero agreed, zero broken, zero differed: every signature was SKIPped.
    # Green here would be a guard that cannot fail.
    echo "  verdict: NOT VERIFIED -- no signature was actually compared ($skipped skipped)."
    exit 2
  fi
  echo "  verdict: pxx's C prologue reads its REGISTER arguments where clang puts them."
  echo "  NOT established here: stack-passed arguments (offsets, not registers), and"
  echo "  aggregates by value -- both need an object writer and a gcc-compiled caller"
  echo "  to settle honestly, which is what this probe's ticket exists to build."
  exit 0
fi
if [ $differed -gt 0 ] || [ $pxx_broke -gt 0 ]; then
  echo "  verdict: DISAGREEMENT -- $differed differing, $pxx_broke pxx-side broken."
  if [ $oracle_broke -gt 0 ]; then
    echo "  ALSO $oracle_broke row(s) failed in the INSTRUMENT (the oracle produced no"
    echo "  list); those are NOT part of this verdict and say nothing about pxx."
  fi
  exit 1
fi
# Only the oracle failed. Nothing was learned about pxx, either way.
# AND DO NOT MINE THE OTHER COUNTERS ON THIS PATH. `$skipped` is DERIVED from
# clang's extracted shape, so when extraction fails it is 0 for that reason and
# for no other -- it is downstream of the failure and carries no independent
# information. This is a real trap and was spotted 2026-09-22 on the borg tail:
# the one visible BROKEN row was `double b1..b9, int a1`, i.e. precisely the
# signature that exhausts v0-v7 and forces the ninth argument onto the stack,
# printed beside `0 skipped (stack-passed)`. That reads exactly like a
# stack-passed classifier failing on the case built to trigger it, and it is
# not: you cannot classify a row as stack-passed having extracted nothing from
# it. A derived counter that looks like an ABI observation is a small trap
# sitting inside a bigger one.
echo "  verdict: INSTRUMENT FAILURE -- $oracle_broke row(s) produced no usable register"
echo "  list from the INSTRUMENT side, so $agreed of $((agreed + oracle_broke)) signature(s) could be compared."
echo "  THIS IS NOT A STATEMENT ABOUT PXX and must not be read as one. The per-row"
echo "  lines above say which side failed: read them before touching the compiler."
echo "  Two candidates, in the order they bite: the DISASSEMBLER ($OBJDUMP) emitting"
echo "  nothing for objects that compiled, and the ORACLE ($CLANG) emitting asm this"
echo "  probe cannot extract from (version, aarch64 target, asm format)."
exit 2
