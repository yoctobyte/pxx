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
# Exit 0 if every signature agrees with clang, 1 on the first disagreement.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PXX="${PXX_PROBE_CC:-$REPO_ROOT/compiler/pascal26}"
CLANG="${CLANG:-clang}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -x "$PXX" ] || { echo "probe: compiler not built ($PXX)" >&2; exit 2; }
command -v "$CLANG" >/dev/null || { echo "probe: clang absent; aarch64 C-ABI prologue NOT verified" >&2; exit 0; }
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

pxx_regs() {
  local withf="$1" nof="$2" a="$WORK/a.a64" b="$WORK/b.a64"
  "$PXX" --target=aarch64 --system-libs=c "$withf" "$a" >/dev/null 2>&1
  "$PXX" --target=aarch64 --system-libs=c "$nof"   "$b" >/dev/null 2>&1
  llvm-objdump-21 -d --triple=aarch64 "$a" 2>/dev/null | sed 's/^[^\t]*\t[^\t]*\t//' > "$WORK/a.txt"
  llvm-objdump-21 -d --triple=aarch64 "$b" 2>/dev/null | sed 's/^[^\t]*\t[^\t]*\t//' > "$WORK/b.txt"
  # `x8, x29, x9` is the slot-address setup both arms emit; the store right
  # after it names the register the argument arrived in, which is the one thing
  # the two conventions disagree about.
  { diff "$WORK/b.txt" "$WORK/a.txt" || true; } | grep '^>' | sed 's/^> //' \
    | awk '/^x8, x29, x9$/{want=1;next} want{r=$1; sub(",","",r); print r; want=0}' || true
}

rc=0
skipped=0
agreed=0
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
  # failure that actually happened, caught only because rc=1 arrived with no
  # rows at all. A register list is also never shorter than the argument count.
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
    printf '            one side produced no register list; this is an INSTRUMENT failure, not a result\n'
    rc=1
    continue
  fi
  if [ "$(printf '%s' "$c" | wc -w)" -lt "$nargs" ] || [ "$(printf '%s' "$p" | wc -w)" -lt "$nargs" ]; then
    printf '  BROKEN  %s\n            fewer stores than arguments (%d): clang [%s] pxx [%s]\n' \
      "$sig" "$nargs" "$c" "$p"
    rc=1
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
    rc=1
  fi
done

echo "aarch64 C-ABI prologue: $agreed signature(s) agree with clang, $skipped skipped (stack-passed)"
if [ $rc -eq 0 ]; then
  echo "  verdict: pxx's C prologue reads its REGISTER arguments where clang puts them."
  echo "  NOT established here: stack-passed arguments (offsets, not registers), and"
  echo "  aggregates by value -- both need an object writer and a gcc-compiled caller"
  echo "  to settle honestly, which is what this probe's ticket exists to build."
else
  echo "  verdict: DISAGREEMENT -- see the rows marked DIFFER or BROKEN."
fi
exit $rc
