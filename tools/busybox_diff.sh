#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# busybox `cat`, built by pxx from UNVENDORED upstream source, against a
# gcc-built binary of the same source -- on x86-64 and aarch64.
#
# This is the success criterion of feature-c-corpus-busybox-applet, made
# repeatable. It is not a unit test: it needs a fetched and configured busybox
# tree, so it lives here rather than in `make test`.
#
# THREE BINARIES, TWO ORACLES. The subject is tools/busybox_cat_unity.c built
# by pxx, once per target. The oracle is the SAME unity built by gcc. When the
# tree also has upstream's own busybox_CAT -- built by busybox's Makefile from
# 25 separate .o files, which is a different build in every respect except the
# source -- that is compared too, and it is the stronger of the two: a unity
# build can share a mistake with itself, it cannot share one with a real link.
#
# THE ORACLE IS gcc AND UPSTREAM. If gcc cannot build the unity, that is a
# FAILURE of this harness and not a pass for pxx -- there is nothing to compare
# against, and reporting "no differences" would be true and worthless.
#
# A MISSING TREE IS AN ERROR, NOT A PASS. It exits non-zero and prints the one
# command that produces it. A harness that skips quietly when its subject is
# absent looks like coverage for as long as nobody checks
# (task-t-the-c-corpus-is-two-rungs-not-four-and-a-missing-tree-reports-pass).
#
# CONFIGURING IS OURS, NOT THE OPERATOR'S. A fetched tree is configured here,
# because the obvious recipe does not work: `make defconfig && make` fails on
# busybox 1.36.1 against a current kernel-headers package (networking/tc.c
# wants struct tc_cbq_lssopt, removed from <linux/pkt_sched.h>), which also
# rules out upstream's make_single_applets.sh -- it needs include/applets.h
# from a completed build. allnoconfig plus CONFIG_CAT never compiles tc.c at
# all. The one non-obvious line is CONFIG_SH_IS_ASH: "sh" aliasing defaults to
# ash even with every applet off, so without turning it off the tree builds
# NUM_APPLETS 2 and is no longer a single-applet build.
#
# THE LAST LINE IS A POSITIVE TOKEN THIS SCRIPT EMITS ITSELF. If you do not see
# BUSYBOX-CAT-DIFF-COMPLETE you did not get a result, whatever the exit status
# says -- a status can come from a `;`-list's last command or a shell that
# never ran the body.
#
# usage: tools/busybox_cat_diff.sh [--pinned] [--keep] [--targets "x86_64 aarch64"]
#   --pinned    use stable_linux_amd64/default/pinned instead of compiler/pascal26
#   --keep      leave the work directory in place and print it
#   --targets   space-separated target list (default: x86_64 aarch64)
# env:
#   PXX_BUSYBOX_DIR   use this tree instead of library_candidates/busybox
#
# The tree is fetched by tools/install_lib_candidates.sh busybox and configured
# by this script; there is no manual step.

set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BB="${PXX_BUSYBOX_DIR:-$ROOT/library_candidates/busybox}"
UNITY="$ROOT/tools/busybox_cat_unity.c"
COMPILER="$ROOT/compiler/pascal26"
TARGETS="x86_64 aarch64"
KEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --pinned)  COMPILER="$ROOT/stable_linux_amd64/default/pinned"; shift ;;
    --keep)    KEEP=1; shift ;;
    --targets) TARGETS="$2"; shift 2 ;;
    *) printf 'busybox-cat-diff: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

die() { printf 'busybox-cat-diff: %s\n' "$*" >&2; exit 1; }

[ -x "$COMPILER" ] || die "no compiler at $COMPILER"
[ -f "$UNITY" ]    || die "no unity source at $UNITY"

if [ ! -d "$BB" ]; then
  cat >&2 <<EOF
busybox-cat-diff: no busybox tree at
  $BB
Fetch it with:
  tools/install_lib_candidates.sh busybox
This script configures and builds it; nothing else is needed.
EOF
  exit 1
fi

configure_tree() {
  printf 'busybox-cat-diff: configuring %s for a single CAT applet\n' "$BB"
  ( cd "$BB" \
    && make allnoconfig >/dev/null 2>&1 \
    && sed -i 's/^# CONFIG_CAT is not set$/CONFIG_CAT=y/' .config \
    && sed -i 's/^CONFIG_SH_IS_ASH=y$/# CONFIG_SH_IS_ASH is not set/' .config \
    && sed -i '/^# CONFIG_SH_IS_NONE is not set$/d' .config \
    && printf 'CONFIG_SH_IS_NONE=y\n' >> .config \
    && yes '' | make oldconfig >/dev/null 2>&1 \
    && make -j"$(nproc 2>/dev/null || echo 4)" ) > "$1" 2>&1
}

if [ ! -f "$BB/include/NUM_APPLETS.h" ] || ! grep -q '^#define NUM_APPLETS 1$' "$BB/include/NUM_APPLETS.h"; then
  CFGLOG="${TMPDIR:-/tmp}/bbcat-configure.log"
  configure_tree "$CFGLOG" || { tail -20 "$CFGLOG" >&2; die "could not configure the tree (log: $CFGLOG)"; }
  grep -q '^#define NUM_APPLETS 1$' "$BB/include/NUM_APPLETS.h" \
    || die "configured tree reports $(tr -d '\n' < "$BB/include/NUM_APPLETS.h"), not a single applet (log: $CFGLOG)"
  rm -f "$CFGLOG"
fi
grep -q '^#define SINGLE_APPLET_MAIN cat_main$' "$BB/include/applet_tables.h" \
  || die "the tree's single applet is not cat"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bbcat-diff-XXXXXX")"
cleanup() { [ "$KEEP" -eq 1 ] && printf 'busybox-cat-diff: work dir kept at %s\n' "$WORK" || rm -rf "$WORK"; }
trap cleanup EXIT

# The version the tree would compile in, so the unity is not built with a
# version string from a different release than the source it includes.
BBVER="$(sed -n 's/^#define BB_VER "\(.*\)"$/\1/p' "$BB/include/bb_config.h" 2>/dev/null | head -1)"
[ -n "$BBVER" ] && VERDEF="-DBB_VER=\"$BBVER\"" || VERDEF=""

INC="-I. -Iinclude -Ilibbb"

printf 'busybox-cat-diff: tree=%s\n' "$BB"
printf 'busybox-cat-diff: compiler=%s\n' "$COMPILER"

# ---- the fixed input set -------------------------------------------------
D="$WORK/data"; mkdir -p "$D"
: > "$D/empty.txt"
printf 'alpha\nbeta\ngamma\n'            > "$D/a.txt"
printf 'one\ntwo\n'                      > "$D/b.txt"
printf 'no trailing newline'             > "$D/nonl.txt"
head -c 4096 /dev/urandom                > "$D/bin.dat"
# missing.txt deliberately does not exist

run_cases() {  # $1 = runner ("" for native), $2 = binary
  local runner="$1" bin="$2" args
  for args in "$D/empty.txt" "$D/a.txt" "$D/bin.dat" "$D/a.txt $D/b.txt" \
              "$D/nonl.txt $D/a.txt" "$D/a.txt - $D/b.txt" "-" "$D/missing.txt" \
              "$D/a.txt $D/missing.txt $D/b.txt" "-u $D/a.txt" \
              "$D/a.txt $D/a.txt $D/a.txt"; do
    printf '### [%s]\n' "$args"
    if [ -n "$runner" ]; then printf 'piped-stdin\n' | $runner "$bin" $args
    else                      printf 'piped-stdin\n' | "$bin" $args; fi
    printf '### exit=%d\n' "$?"
  done
  printf '### no-args (stdin)\n'
  if [ -n "$runner" ]; then printf 'x\ny\n' | $runner "$bin"
  else                      printf 'x\ny\n' | "$bin"; fi
  printf '### exit=%d\n' "$?"
}

RC=0

# ---- oracle: gcc on the same unity ---------------------------------------
command -v gcc >/dev/null 2>&1 || die "gcc is the oracle and is not installed"
( cd "$BB" && gcc -w -O2 -D_GNU_SOURCE $VERDEF $INC -o "$WORK/oracle_gcc" "$UNITY" ) \
  || die "gcc could NOT build the unity -- no oracle, so no result"
run_cases "" "$WORK/oracle_gcc" > "$WORK/oracle_gcc.out" 2>&1
printf '  ORACLE  gcc unity build\n'

# ---- second oracle: upstream's own separately-linked binary --------------
UPSTREAM=""
for cand in "$BB/busybox_CAT" "$BB/busybox"; do
  [ -x "$cand" ] && { UPSTREAM="$cand"; break; }
done
if [ -n "$UPSTREAM" ]; then
  run_cases "" "$UPSTREAM" > "$WORK/oracle_upstream.out" 2>&1
  if cmp -s "$WORK/oracle_gcc.out" "$WORK/oracle_upstream.out"; then
    printf '  ORACLE  %s agrees with the gcc unity\n' "$(basename "$UPSTREAM")"
  else
    printf '  FAIL    the two ORACLES disagree -- the unity is not equivalent to a real link\n'
    diff "$WORK/oracle_gcc.out" "$WORK/oracle_upstream.out" | head -20
    RC=1
  fi
else
  printf '  note    no separately-linked busybox in the tree; gcc unity is the only oracle\n'
fi

# ---- subjects ------------------------------------------------------------
for t in $TARGETS; do
  out="$WORK/pxx_$t"
  if [ "$t" = "x86_64" ]; then targflag=""; runner=""
  else targflag="--target=$t"; runner="$ROOT/tools/run_target.sh $t"; fi

  if ! ( cd "$BB" && "$COMPILER" $targflag $INC "$UNITY" "$out" ) > "$WORK/build_$t.log" 2>&1; then
    printf '  FAIL    %-8s pxx could not build the unity\n' "$t"
    grep -v '^ok:' "$WORK/build_$t.log" | head -10
    RC=1; continue
  fi

  # Per-case exit statuses are part of the compared OUTPUT (run_cases prints
  # them), so this call's own status carries no information and is ignored.
  run_cases "$runner" "$out" > "$WORK/pxx_$t.out" 2>&1 || true

  if cmp -s "$WORK/oracle_gcc.out" "$WORK/pxx_$t.out"; then
    printf '  PASS    %-8s byte-identical to the gcc oracle over %d cases\n' \
           "$t" "$(grep -c '^### \[' "$WORK/oracle_gcc.out")"
  else
    printf '  FAIL    %-8s differs from the gcc oracle\n' "$t"
    diff "$WORK/oracle_gcc.out" "$WORK/pxx_$t.out" | head -30
    RC=1
  fi
done

[ "$RC" -eq 0 ] && printf 'busybox-cat-diff: GREEN\n' || printf 'busybox-cat-diff: RED\n'
printf 'BUSYBOX-CAT-DIFF-COMPLETE\n'
exit "$RC"
