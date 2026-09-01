#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# busybox built by pxx from UNVENDORED upstream source, against a gcc-built
# binary of the same source -- on x86-64 and aarch64.
#
# Rung 1 (`--applets cat`) is the success criterion of
# feature-c-corpus-busybox-applet, made repeatable. Rung 2 (two or more
# applets, the default) is feature-c-corpus-busybox-multi-applet: it turns on
# the applet DISPATCH TABLE, which a single-applet build compiles out
# (NUM_APPLETS 1 sets SINGLE_APPLET_MAIN and there is no table at all).
#
# It is not a unit test: it needs a fetched and configured busybox tree, so it
# lives here rather than in `make test`.
#
# THREE BINARIES, TWO ORACLES. The subject is a unity translation unit built by
# pxx, once per target. The oracle is the SAME unity built by gcc. When the tree
# also has upstream's own separately-linked binary -- built by busybox's own
# Makefile from N separate .o files, which is a different build in every respect
# except the source -- that is compared too, and it is the stronger of the two:
# a unity build can share a mistake with itself, it cannot share one with a real
# link.
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
# from a completed build. allnoconfig plus the applet list never compiles tc.c
# at all. The one non-obvious line is CONFIG_SH_IS_ASH: "sh" aliasing defaults
# to ash even with every applet off, so without turning it off the tree builds
# one applet more than was asked for.
#
# THE UNITY IS GENERATED FROM THE MAP, not maintained by hand. busybox decides
# which archive members a link pulls; busybox_unstripped.map records the answer;
# this reads it. The PREAMBLE -- the #defines that make a unity build equivalent
# to a real link, and the reason appletlib.c must come first -- is not
# duplicated here: it is read verbatim out of tools/busybox_cat_unity.c, which
# is where those facts are written down and where they stay.
#
# POSITIVE CONTROL. For the single-`cat` configuration the generated include
# list MUST equal the one in tools/busybox_cat_unity.c -- the 25 members rung 1
# was measured over. That is a case the generator can FAIL, asserted every run,
# so "the map-derived list looks plausible" is never the whole of the evidence.
# A generator with no case it must reject is not a generator, it is a printer.
#
# THE LAST LINE IS A POSITIVE TOKEN THIS SCRIPT EMITS ITSELF. If you do not see
# BUSYBOX-DIFF-COMPLETE you did not get a result, whatever the exit status says
# -- a status can come from a `;`-list's last command or a shell that never ran
# the body.
#
# usage: tools/busybox_diff.sh [--pinned] [--keep] [--targets "x86_64 aarch64"]
#                              [--applets "cat echo"]
#   --pinned    use stable_linux_amd64/default/pinned instead of compiler/pascal26
#   --keep      leave the work directory in place and print it
#   --targets   space-separated target list (default: x86_64 aarch64)
#   --applets   space-separated applet list (default: cat echo -- rung 2).
#               A single applet reproduces rung 1 exactly.
#   --separate  build busybox the way BUSYBOX does -- one object per translation
#               unit and a real link -- instead of as a unity. x86_64 only,
#               because --emit-obj has no aarch64 object writer yet. This is a
#               STRICTLY STRONGER claim than the unity: it needs no include
#               ordering, no ASH_TEST exclusion, and no preamble tricks, so it
#               is the configuration that scales past the handful of applets a
#               unity can hold. It currently needs -Wl,-z,muldefs; see
#               bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link.
# env:
#   PXX_BUSYBOX_DIR   use this tree instead of library_candidates/busybox
#
# The tree is fetched by tools/install_lib_candidates.sh busybox and configured
# by this script; there is no manual step.

set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BB="${PXX_BUSYBOX_DIR:-$ROOT/library_candidates/busybox}"
CATUNITY="$ROOT/tools/busybox_cat_unity.c"
COMPILER="$ROOT/compiler/pascal26"
TARGETS="x86_64 aarch64"
APPLETS="cat echo"
KEEP=0
SEPARATE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --pinned)  COMPILER="$ROOT/stable_linux_amd64/default/pinned"; shift ;;
    --keep)    KEEP=1; shift ;;
    --targets) TARGETS="$2"; shift 2 ;;
    --applets) APPLETS="$2"; shift 2 ;;
    --separate) SEPARATE=1; shift ;;
    *) printf 'busybox-diff: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

die() { printf 'busybox-diff: %s\n' "$*" >&2; exit 1; }

[ -x "$COMPILER" ] || die "no compiler at $COMPILER"
[ -f "$CATUNITY" ] || die "no unity preamble source at $CATUNITY"

NAPPLETS=$(printf '%s\n' $APPLETS | wc -l)
[ "$NAPPLETS" -ge 1 ] || die "--applets needs at least one applet"

if [ ! -d "$BB" ]; then
  cat >&2 <<EOF
busybox-diff: no busybox tree at
  $BB
Fetch it with:
  tools/install_lib_candidates.sh busybox
This script configures and builds it; nothing else is needed.
EOF
  exit 1
fi

# ---- configure --------------------------------------------------------------
# ONE list, used both to configure the tree and to decide whether an existing
# tree already matches. Two copies is how the first two runs of this went wrong:
# the tree was configured for 3 applets with every ash feature off, the
# "already configured?" test only asked about the applet COUNT, so the
# reconfigure was skipped and the comparison would have run against a shell
# that cannot do arithmetic. Whatever configure_tree turns on, ash_features_ok
# must ask about -- including what it deliberately leaves OFF.
ASH_ON="FEATURE_SH_MATH FEATURE_SH_MATH_64 FEATURE_SH_MATH_BASE \
        ASH_ALIAS ASH_ECHO ASH_PRINTF ASH_CMDCMD \
        ASH_GETOPTS ASH_BASH_COMPAT ASH_INTERNAL_GLOB"
ASH_OFF="ASH_TEST ASH_RANDOM_SUPPORT ASH_JOB_CONTROL ASH_IDLE_TIMEOUT \
         ASH_MAIL ASH_EXPAND_PRMT FEATURE_EDITING FEATURE_SH_STANDALONE \
         FEATURE_SH_NOFORK"
# CONFIG_BUSYBOX is the `busybox` multiplexer applet itself. Off for a single
# applet (rung 1's configuration, unchanged); ON as soon as there is more than
# one, because `busybox <applet>` dispatch and `busybox --list` are half of what
# rung 2 exists to test -- the other half being argv[0].
configure_tree() {
  local log="$1" a
  printf 'busybox-diff: configuring %s for applets: %s\n' "$BB" "$APPLETS"
  (
    cd "$BB" || exit 1
    make allnoconfig >/dev/null 2>&1 || exit 1
    for a in $APPLETS; do
      A=$(printf '%s' "$a" | tr 'a-z-' 'A-Z_')
      grep -q "^# CONFIG_$A is not set$" .config \
        || { printf 'no CONFIG_%s in this busybox\n' "$A" >&2; exit 1; }
      sed -i "s/^# CONFIG_$A is not set\$/CONFIG_$A=y/" .config
    done
    if [ "$NAPPLETS" -gt 1 ]; then
      sed -i 's/^# CONFIG_BUSYBOX is not set$/CONFIG_BUSYBOX=y/' .config
    fi
    sed -i 's/^CONFIG_SH_IS_ASH=y$/# CONFIG_SH_IS_ASH is not set/' .config
    sed -i '/^# CONFIG_SH_IS_NONE is not set$/d' .config
    printf 'CONFIG_SH_IS_NONE=y\n' >> .config
    # ash under allnoconfig is a SHELL THAT CANNOT DO ARITHMETIC: every ASH_*
    # and FEATURE_SH_MATH knob is off, so `echo $((1+1))` is a syntax error.
    # Comparing two builds of that is the guard-that-cannot-fail shape -- green,
    # and testing nothing a shell is for. Turn on what a real /bin/sh has,
    # MINUS everything nondeterministic or interactive, because this harness
    # compares transcripts byte for byte:
    #   ASH_RANDOM_SUPPORT   $RANDOM -- entropy
    #   ASH_JOB_CONTROL      scheduling order
    #   ASH_IDLE_TIMEOUT ASH_MAIL ASH_EXPAND_PRMT FEATURE_EDITING*
    #                        interactive-only, and EDITING reads the terminal
    #   FEATURE_SH_STANDALONE FEATURE_SH_NOFORK
    #                        change whether a child is a fork or an in-process
    #                        call, which is a different program, not a faster one
    if printf '%s\n' $APPLETS | grep -qx ash; then
      # ASH_TEST IS DELIBERATELY ABSENT, and it is the unity model's ceiling
      # rather than a preference. It pulls coreutils/test.c, which claims 6
      # ordinary identifiers through the same globals-macro pattern ash claims
      # 43 through, and the two collide in BOTH directions (measured, gcc):
      #   test.c first : ./coreutils/test.c:441 #define args (S.args)
      #                  breaks ash.c:12025 `union node *args, **app;'
      #   ash.c  first : ./shell/ash.c:495 #define arg0 (G_misc.arg0)
      #                  breaks test.c:897
      # No include order satisfies both, so this is the first thing rung 2 wants
      # that separate compilation is REQUIRED for, not merely tidier. Losing it
      # costs the `[' builtin, so the cases below use `case $((expr)) in' for
      # their conditions. echo.c and printf.c do NOT use the pattern (0 such
      # macros each), so ASH_ECHO/ASH_PRINTF stay on.
      for f in $ASH_ON; do
        sed -i "s/^# CONFIG_$f is not set\$/CONFIG_$f=y/" .config
      done
      for f in $ASH_OFF; do
        sed -i "s/^CONFIG_$f=y\$/# CONFIG_$f is not set/" .config
      done
    fi
    yes '' | make oldconfig >/dev/null 2>&1 || exit 1
    make -j"$(nproc 2>/dev/null || echo 4)"
  ) > "$log" 2>&1
}

want_num_applets() { printf '#define NUM_APPLETS %s\n' "$NAPPLETS"; }

# Whether the tree already matches what was asked for. The applet COUNT is not
# sufficient: a tree configured for `cat echo ash` with every ASH_* knob off has
# the right NUM_APPLETS and the wrong shell, and skipping the reconfigure on
# that basis is how the first run of this got a stub. Ask about the features too.
#
# THE COUNT IS NOT SUFFICIENT IN THE OTHER DIRECTION EITHER, and that half was
# missed when the ash half above was fixed. `cat echo ash ls` and
# `cat echo ash wc` are both NUM_APPLETS 4 with identical ash knobs, so a run
# asking for the second was served the first and never reconfigured. Measured
# 2026-09-01, and it silently turned a twelve-applet sweep into ONE applet
# measured twelve times -- twelve identical failures that looked like
# overwhelming agreement and were one data point. The identity of the applets
# is the thing being asked about, so ask about it.
applets_ok() {
  local a A
  [ -f "$BB/.config" ] || return 1
  for a in $APPLETS; do
    A="$(printf '%s' "$a" | tr 'a-z-' 'A-Z_')"
    grep -qx "CONFIG_$A=y" "$BB/.config" || return 1
  done
  # Nothing EXTRA needs no separate check: this asks that every requested
  # applet is on, and the NUM_APPLETS test beside it asks that the total is
  # exactly $NAPPLETS. All-present plus right-count is the exact set.
  return 0
}

ash_features_ok() {
  local f
  printf '%s\n' $APPLETS | grep -qx ash || return 0
  [ -f "$BB/.config" ] || return 1
  for f in $ASH_ON;  do grep -qx "CONFIG_$f=y" "$BB/.config" || return 1; done
  for f in $ASH_OFF; do grep -qx "CONFIG_$f=y" "$BB/.config" && return 1; done
  return 0
}

if [ ! -f "$BB/include/NUM_APPLETS.h" ] \
   || ! grep -qx "$(want_num_applets)" "$BB/include/NUM_APPLETS.h" \
   || ! applets_ok \
   || ! ash_features_ok \
   || ! grep -qx "$(printf '#define ENABLE_BUSYBOX %s' "$([ "$NAPPLETS" -gt 1 ] && echo 1 || echo 0)")" "$BB/include/autoconf.h"; then
  CFGLOG="${TMPDIR:-/tmp}/bbdiff-configure.log"
  configure_tree "$CFGLOG" || { tail -20 "$CFGLOG" >&2; die "could not configure the tree (log: $CFGLOG)"; }
  grep -qx "$(want_num_applets)" "$BB/include/NUM_APPLETS.h" \
    || die "configured tree reports $(tr -d '\n' < "$BB/include/NUM_APPLETS.h"), not $NAPPLETS applet(s) (log: $CFGLOG)"
  rm -f "$CFGLOG"
fi

# `make oldconfig` resolves dependencies and will silently drop a knob whose
# deps are unmet, so asking for CONFIG_FEATURE_SH_MATH is not the same as
# getting it -- and the symptom would be a GREEN run over a stub shell.
if printf '%s\n' $APPLETS | grep -qx ash; then
  for f in $ASH_ON; do
    grep -qx "CONFIG_$f=y" "$BB/.config" \
      || die "oldconfig dropped CONFIG_$f -- the shell under test is not the one asked for (without FEATURE_SH_MATH, \$((arith)) is a syntax error and the whole comparison is over a stub)"
  done
  for f in $ASH_OFF; do
    grep -qx "CONFIG_$f=y" "$BB/.config" \
      && die "CONFIG_$f is on and must not be -- it is either nondeterministic across runs or collides in the unity (see configure_tree)"
  done
fi

# The dispatch table is the POINT of rung 2, so assert which build we got rather
# than inferring it from the applet count: SINGLE_APPLET_MAIN present means the
# table was compiled out and nothing below tests it.
if [ "$NAPPLETS" -eq 1 ]; then
  grep -q "^#define SINGLE_APPLET_MAIN ${APPLETS}_main\$" "$BB/include/applet_tables.h" \
    || die "the tree's single applet is not $APPLETS"
else
  grep -q '^#define SINGLE_APPLET_MAIN' "$BB/include/applet_tables.h" \
    && die "tree still has SINGLE_APPLET_MAIN: the applet dispatch table is compiled out, so this run would test nothing it claims to"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bbdiff-XXXXXX")"
cleanup() { [ "$KEEP" -eq 1 ] && printf 'busybox-diff: work dir kept at %s\n' "$WORK" || rm -rf "$WORK"; }
trap cleanup EXIT

# ---- the unity, generated from the link map ---------------------------------
# The map names archive MEMBERS (`foo.o`); the include list needs their SOURCES.
# crtbegin/crtend are the toolchain's, not busybox's, and appletlib is emitted
# by the preamble because its position is load-bearing (see busybox_cat_unity.c).
UNITY="$WORK/busybox_unity.c"
MAP="$BB/busybox_unstripped.map"
[ -f "$MAP" ] || die "no $MAP -- the tree built no map, so the member list cannot be read"

# The version the tree would compile in, so the unity is not built with a
# version string from a different release than the source it includes. It lives
# in the top-level Makefile (Makefile.flags builds -DBB_VER from it); there is
# no header to read it out of, and a previous cut of this script looked for one
# that has never existed -- so BB_VER silently fell back to the hardcoded tag
# for the whole of rung 1. Harmless there (nothing `cat` prints contains it) and
# still worth reading from the one place that has it.
bbver_field() { sed -n "s/^$1 *= *//p" "$BB/Makefile" | head -1 | tr -d ' \t'; }
BBVER="$(bbver_field VERSION).$(bbver_field PATCHLEVEL).$(bbver_field SUBLEVEL)$(bbver_field EXTRAVERSION)"
case "$BBVER" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) die "could not read a version out of $BB/Makefile (got '$BBVER')" ;;
esac

# Preamble: everything in busybox_cat_unity.c up to and including the
# appletlib.c include. One copy of those facts, in the file that documents them.
sed -n '1,/^#include "libbb\/appletlib.c"$/p' "$CATUNITY" > "$UNITY"
grep -q '^#include "libbb/appletlib.c"$' "$UNITY" \
  || die "$CATUNITY no longer ends its preamble with the appletlib.c include"

gen_includes() {   # member basenames -> #include lines, appletlib/crt* removed
  local o src
  grep -oE '[a-z_0-9]+\.o\)' "$MAP" | sed 's/\.o)$//' | sort -u \
    | grep -vxE 'crtbegin|crtend|crti|crtn|appletlib' \
    | while read -r o; do
        src="$(cd "$BB" && find . -name "$o.c" -not -path './scripts/*' -not -path './examples/*' \
                            | sed 's|^\./||' | sort | head -1)"
        [ -n "$src" ] || { printf 'no source file for archive member %s.o\n' "$o" >&2; return 1; }
        printf '#include "%s"\n' "$src"
      done
}

gen_includes > "$WORK/includes.txt.raw" || die "could not map every archive member to a source file"
[ -s "$WORK/includes.txt.raw" ] || die "the map yielded no archive members -- refusing to build an empty unity"

# SECOND ORDERING CONSTRAINT, and it is the mirror of appletlib.c's "must come
# FIRST": shell/*.c must come LAST.
#
# shell/ash.c reaches its globals through 40 #defines of very ordinary names --
# `#define optlist (G_misc.optlist)`, and then `#define eflag optlist[0]`. Those
# are TU-local in a real link and leak forward in a unity. Measured with gcc,
# which is the whole reason this is here rather than being my theory:
#
#   ./shell/ash.c:503:21: error: expected identifier before '(' token
#     503 | #define optlist     (G_misc.optlist    )
#   ./shell/ash.c:428:15: note: in expansion of macro 'optlist'
#     428 | #define eflag optlist[0]
#   ./coreutils/echo.c:93:17: note: in expansion of macro 'eflag'
#      93 |     eflag = 0,  /* 0 -- disable escape sequences */
#
# echo.c's own local variable `eflag` became `G_misc.optlist[0]`. Moving the
# shell to the end builds clean under gcc with zero diagnostics. Note what this
# is NOT: not a pxx defect, not a busybox defect. It is the unity build model
# reaching its ceiling on a file that assumes it owns its namespace -- so it is
# EVIDENCE FOR separate compilation, not a workaround that removes the need.
# The next such file (hush.c) cannot be ordered around this one.
grep -v '^#include "shell/'  "$WORK/includes.txt.raw" >  "$WORK/includes.txt"
grep    '^#include "shell/'  "$WORK/includes.txt.raw" >> "$WORK/includes.txt" || true
cat "$WORK/includes.txt" >> "$UNITY"

# The ordering above is load-bearing and silent when wrong (it fails as a
# confusing error inside an unrelated applet), so assert the artifact has it.
if grep -q '^#include "shell/' "$WORK/includes.txt"; then
  tail -1 "$WORK/includes.txt" | grep -q '^#include "shell/' \
    || die "a shell TU is not last in the generated unity -- ash's macros will leak into whatever follows"
  # No ordering saves this pair (see the ASH_TEST note in configure_tree), so
  # catch it here with its cause rather than as 200 lines of gcc errors blaming
  # a macro expansion three files away.
  grep -q '^#include "coreutils/test.c"$' "$WORK/includes.txt" \
    && die "coreutils/test.c and shell/ash.c both claim ordinary identifiers via globals macros and collide in BOTH include orders -- this unity cannot contain both. Separate compilation is the fix; turning ASH_TEST back on is not."
fi

# POSITIVE CONTROL: for the cat-only configuration the generated list must be
# exactly rung 1's. Anything else means the generator drifted from the file the
# byte-identical claim was measured over, and the run stops.
if [ "$APPLETS" = "cat" ]; then
  sed -n '/^#include "libbb\/appletlib.c"$/,$p' "$CATUNITY" | sed 1d | sort > "$WORK/control_want.txt"
  sort "$WORK/includes.txt" > "$WORK/control_got.txt"
  if ! cmp -s "$WORK/control_want.txt" "$WORK/control_got.txt"; then
    printf '  FAIL    generated include list differs from %s\n' "$CATUNITY"
    diff "$WORK/control_want.txt" "$WORK/control_got.txt"
    die "the generator does not reproduce rung 1's translation unit"
  fi
  printf '  CONTROL generated include list == %s (%d members)\n' \
         "$(basename "$CATUNITY")" "$(wc -l < "$WORK/includes.txt")"
fi

INC="-I. -Iinclude -Ilibbb"
NTU=$(( $(wc -l < "$WORK/includes.txt") + 1 ))

# How many CASES a comparison covered -- the number the PASS line reports, so it
# has to be right. Two things make the obvious spelling wrong, and both were
# measured here rather than reasoned about:
#   * `-a`, because one case cats 4KB of /dev/urandom. Without it grep decides
#     the transcript is binary, prints "binary file matches" instead of the
#     lines, and the count is 0 -- which printed `PASS ... over 0 cases`.
#   * exclude `### exit=`, because each case prints one, and one of THOSE does
#     not start a line at all: cat'ing nonl.txt leaves the cursor mid-line, so
#     that marker is glued to the file's last bytes. Counting every `^### `
#     reported 23 for 12 cases.
count_cases() { grep -a '^### ' "$1" | grep -avc '^### exit='; }

printf 'busybox-diff: tree=%s (busybox %s)\n' "$BB" "$BBVER"
printf 'busybox-diff: compiler=%s\n' "$COMPILER"
printf 'busybox-diff: sha256=%s\n' "$(sha256sum "$COMPILER" | cut -d' ' -f1)"
printf 'busybox-diff: applets=%s  translation units=%d\n' "$APPLETS" "$NTU"

# ---- the fixed input set ----------------------------------------------------
D="$WORK/data"; mkdir -p "$D"
: > "$D/empty.txt"
printf 'alpha\nbeta\ngamma\n'            > "$D/a.txt"
printf 'one\ntwo\n'                      > "$D/b.txt"
printf 'no trailing newline'             > "$D/nonl.txt"
head -c 4096 /dev/urandom                > "$D/bin.dat"
# missing.txt deliberately does not exist

# A binary is INSTALLED into its own directory as `busybox` plus one symlink per
# applet, because argv[0] is what a multi-applet build dispatches on. For a
# single-applet build the layout is harmless and the direct invocation below is
# byte-for-byte rung 1's.
install_bin() {   # $1 = dir, $2 = binary
  local a
  mkdir -p "$1"
  cp "$2" "$1/busybox"
  for a in $APPLETS; do ln -sf busybox "$1/$a"; done
}

run_one() {   # $1 = runner ("" native), $2 = argv[0] path, rest = args
  local runner="$1" bin="$2"; shift 2
  if [ -n "$runner" ]; then printf 'piped-stdin\n' | $runner "$bin" "$@"
  else                      printf 'piped-stdin\n' | "$bin" "$@"; fi
}

# Rung 1's case list, unchanged and in its original order, so a single-applet
# run reproduces the resolved ticket's measurement rather than something near it.
run_cat_cases() {   # $1 = runner, $2 = the path to invoke cat through
  local runner="$1" bin="$2" args
  for args in "$D/empty.txt" "$D/a.txt" "$D/bin.dat" "$D/a.txt $D/b.txt" \
              "$D/nonl.txt $D/a.txt" "$D/a.txt - $D/b.txt" "-" "$D/missing.txt" \
              "$D/a.txt $D/missing.txt $D/b.txt" "-u $D/a.txt" \
              "$D/a.txt $D/a.txt $D/a.txt"; do
    printf '### [%s]\n' "$args"
    run_one "$runner" "$bin" $args
    printf '### exit=%d\n' "$?"
  done
  printf '### no-args (stdin)\n'
  if [ -n "$runner" ]; then printf 'x\ny\n' | $runner "$bin"
  else                      printf 'x\ny\n' | "$bin"; fi
  printf '### exit=%d\n' "$?"
}

# Everything a single applet cannot reach: the dispatch table, both ways in.
run_dispatch_cases() {   # $1 = runner, $2 = install dir
  local runner="$1" dir="$2" a
  for a in $APPLETS; do
    printf '### argv0 [%s]\n' "$a"
    run_one "$runner" "$dir/$a" --help
    printf '### exit=%d\n' "$?"
    printf '### busybox-arg [%s]\n' "$a"
    run_one "$runner" "$dir/busybox" "$a" --help
    printf '### exit=%d\n' "$?"
  done
  printf '### --list\n';        run_one "$runner" "$dir/busybox" --list;        printf '### exit=%d\n' "$?"
  printf '### --help\n';        run_one "$runner" "$dir/busybox" --help;        printf '### exit=%d\n' "$?"
  printf '### no-such-applet\n'; run_one "$runner" "$dir/busybox" nosuchapplet;  printf '### exit=%d\n' "$?"
  printf '### bare busybox\n';  run_one "$runner" "$dir/busybox";               printf '### exit=%d\n' "$?"
}

run_echo_cases() {   # $1 = runner, $2 = install dir
  local runner="$1" dir="$2" args
  for args in "hello world" "-n no-newline" "-e a\tb" "-e esc\\\\n" "" "-" "--" \
              "-n -e x\ty"; do
    printf '### echo [%s]\n' "$args"
    run_one "$runner" "$dir/echo" $args
    printf '### exit=%d\n' "$?"
  done
}

has_applet() { case " $APPLETS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ---- ash ---------------------------------------------------------------------
# Rung 2's second bar. Two constraints shape every case below, and both are
# about what a SHELL drags in that cat and echo do not:
#
# 1. BUILTINS ONLY -- no `sort`, `tr`, `wc`, `ls`, not even `cat`. Under
#    tools/run_target.sh the shell itself runs on qemu-user, so any command it
#    execs is a NATIVE binary being started by an emulated process. Those rows
#    would fail for reasons that have nothing to do with codegen, which is the
#    worst kind of red. Forks (subshells, pipelines, command substitution) are
#    fine and are exercised deliberately; it is exec of a foreign binary that is
#    out. This is also why FEATURE_SH_STANDALONE stays off -- it would turn some
#    of these into in-process applet calls and quietly change what is tested.
# 2. NOTHING THAT CARRIES THE ENVIRONMENT. $$ $PPID $RANDOM $SECONDS, dates,
#    `jobs`, and $0 (the install dir differs between oracle and subject) all
#    differ between two builds of the SAME program, so they would diff as
#    failures. ASH_RANDOM_SUPPORT and ASH_JOB_CONTROL are off for this reason.
#
# Each script takes a scratch dir as $1 and prints its own `### ` markers, so a
# divergence names the case rather than just the group.
write_ash_scripts() {   # $1 = dir
  local d="$1"
  mkdir -p "$d"

  cat > "$d/01_arith.sh" <<'ASH'
echo "### ash arith"
echo $((3+4*2)) $((7/2)) $((7%2)) $((1<<10)) $((-3*-3))
x=5; echo $((x+1)) $((x*x)) $((x>3)) $((x==5)) $((x!=5))
echo $((0x10)) $((010)) $(( (1+2)*3 )) $(( 7&3 )) $(( 7|8 )) $(( 7^3 ))
echo $(( 1 && 0 )) $(( 1 || 0 )) $(( !0 )) $(( ~0 ))
echo "### ash arith 64-bit"
echo $(( 1 << 40 )) $(( 2147483647 + 1 )) $(( -9223372036854775807 - 1 ))
ASH

  cat > "$d/02_param.sh" <<'ASH'
echo "### ash parameter expansion"
x=abcdef
echo ${#x} ${x#a} ${x%f} ${x##*c} ${x%%c*}
unset u; y=set
echo ${u:-def} ${u:+no} ${y:+yes} ${u-D} ${y-E}
echo "### ash bash-compat substring"
echo ${x:2:3} ${x:0:1} ${x:4}
echo "### ash positional"
set -- a b c
echo $# $1 $3 "$@" "$*"
set -- a b c d; shift 2; echo $#-$1-$2
echo "### ash quoting"
echo 'a  b' "c  d" e\ \ f "it's" '$notexpanded'
v=w; echo "$v${v}x" '${v}'
ASH

  cat > "$d/03_control.sh" <<'ASH'
echo "### ash for/while/until"
for i in 1 2 3; do printf %s $i; done; echo
i=0; while case $((i<4)) in 1) true;; *) false;; esac; do i=$((i+1)); printf %s $i; done; echo
i=0; until case $((i>=3)) in 1) true;; *) false;; esac; do i=$((i+1)); done; echo $i
for i in 1 2 3 4 5; do case $i in 3) continue;; esac; printf %s $i; done; echo
for i in 1 2 3 4 5; do case $i in 4) break;; esac; printf %s $i; done; echo
echo "### ash case"
for w in aa bb cc dd; do case $w in aa) printf A;; bb|cc) printf B;; *) printf Z;; esac; done; echo
for w in abc a.c xyz; do case $w in a?c) printf Q;; a*) printf S;; *) printf N;; esac; done; echo
echo "### ash and/or/status"
true && echo yes; false || echo no; false && echo bad; echo $?
(exit 42); echo $?
if case $((1<2)) in 1) true;; *) false;; esac; then echo lt; else echo none; fi
echo "### ash arithmetic conditions"
x=7; case $((x%2)) in 1) echo odd;; 0) echo even;; esac
echo $((3>2)) $((3<2)) $((3>=3)) $((2!=2))
ASH

  cat > "$d/04_func.sh" <<'ASH'
echo "### ash functions"
f() { echo "f($1,$2)"; return 3; }
f x y; echo $?
g() { local v=in; echo $v; }
v=out; g; echo $v
rec() { case $(($1<=0)) in 1) return;; esac; printf %s $1; rec $(( $1 - 1 )); }
rec 5; echo
echo "### ash command substitution"
echo "[$(echo nested $(echo deep))]"
echo "[`echo old`]"
n=$(printf 'a\nb\n'); echo "[$n]"
echo "### ash subshell vs group"
v=1; (v=2); echo $v; { v=3; }; echo $v
echo "### ash eval"
w=world; eval 'echo hello $w'
echo "### ash command -v"
command -v echo; command -v printf
ASH

  cat > "$d/05_redir.sh" <<'ASH'
echo "### ash redirection"
d=$1
echo hi > "$d/r1"; echo bye >> "$d/r1"
while read l; do printf '<%s>' "$l"; done < "$d/r1"; echo
echo "### ash heredoc"
while read l; do printf '[%s]' "$l"; done <<EOF
line $((1+1))
$w plain
EOF
echo
while read l; do printf '[%s]' "$l"; done <<'EOF'
no $expansion here
EOF
echo
echo "### ash read from pipe"
printf 'l1\nl2\n' | { read a; read b; echo "$b/$a"; }
echo "### ash glob"
: > "$d/g1"; : > "$d/g2"; : > "$d/h3"
( cd "$d" && echo g* h* z* )
echo "### ash printf builtin"
printf '%s|%d|%x|%o|%c\n' str 42 255 8 A
printf '%5s|%-5s|%05d\n' r l 42
ASH

  cat > "$d/06_misc.sh" <<'ASH'
echo "### ash IFS and word splitting"
old=$IFS; IFS=:; set -- $(echo a:b:c); echo $#-$1-$3; IFS=$old
echo "### ash trap EXIT"
( trap 'echo trapped' EXIT; echo body )
echo "### ash set -e"
( set -e; false; echo NOTREACHED ); echo $?
echo "### ash set -u"
( set -u; echo ${nope} ) 2>/dev/null; echo $?
echo "### ash getopts"
set -- -a -b val rest
while getopts ab: o 2>/dev/null; do echo "opt=$o arg=$OPTARG"; done
shift $((OPTIND-1)); echo "rest=$1"
echo "### ash exit code propagation"
f() { return 7; }; f || echo "got $?"
ASH
}

run_ash_cases() {   # $1 = runner, $2 = install dir
  local runner="$1" dir="$2" f
  write_ash_scripts "$dir/ashsrc"
  rm -rf "$dir/ashtmp"; mkdir -p "$dir/ashtmp"
  for f in "$dir/ashsrc"/*.sh; do
    printf '### ash script [%s]\n' "$(basename "$f")"
    run_one "$runner" "$dir/ash" "$f" "$dir/ashtmp"
    printf '### exit=%d\n' "$?"
  done
}


run_cases() {   # $1 = runner, $2 = install dir
  local runner="$1" dir="$2"
  if [ "$NAPPLETS" -eq 1 ]; then
    run_cat_cases "$runner" "$dir/busybox"
    return
  fi
  run_dispatch_cases "$runner" "$dir"
  has_applet cat  && run_cat_cases  "$runner" "$dir/cat"
  has_applet echo && run_echo_cases "$runner" "$dir"
  has_applet ash  && run_ash_cases  "$runner" "$dir"
  return 0
}

RC=0

# ---- oracle: gcc on the same unity ------------------------------------------
command -v gcc >/dev/null 2>&1 || die "gcc is the oracle and is not installed"
( cd "$BB" && gcc -w -O2 -D_GNU_SOURCE -DBB_VER="\"$BBVER\"" $INC -o "$WORK/oracle_gcc" "$UNITY" ) \
  || die "gcc could NOT build the unity -- no oracle, so no result"
install_bin "$WORK/g" "$WORK/oracle_gcc"
run_cases "" "$WORK/g" > "$WORK/oracle_gcc.out" 2>&1
NCASES="$(count_cases "$WORK/oracle_gcc.out")"
# A comparison over zero cases is the failure this whole script is shaped
# against: cmp of two empty transcripts is GREEN and means nothing. The count
# is load-bearing, so it is asserted rather than merely printed.
[ "$NCASES" -gt 0 ] || die "the oracle transcript holds no cases -- a byte-identical result over nothing is not a result"
printf '  ORACLE  gcc unity build (%d cases)\n' "$NCASES"

# ---- second oracle: upstream's own separately-linked binary -----------------
UPSTREAM=""
for cand in "$BB/busybox_$(printf '%s' "$APPLETS" | tr 'a-z' 'A-Z')" "$BB/busybox"; do
  [ -x "$cand" ] && { UPSTREAM="$cand"; break; }
done
if [ -n "$UPSTREAM" ]; then
  install_bin "$WORK/u" "$UPSTREAM"
  run_cases "" "$WORK/u" > "$WORK/oracle_upstream.out" 2>&1
  # The unity PINS BB_EXTRA_VERSION (see the preamble); upstream's binary has
  # whatever AUTOCONF_TIMESTAMP its libbb/messages.o was built with, which
  # busybox does not rebuild when only that stamp moves. The banner is
  # therefore build metadata on this one axis and is normalised out of THIS
  # comparison only -- the gcc-vs-pxx comparison below stays byte-exact, both
  # sides being built from the same pinned unity. Nothing else is normalised.
  norm_banner() {
    sed 's/^BusyBox v[^ ]* (.*) multi-call binary\.$/BusyBox vX (X) multi-call binary./'
  }
  norm_banner < "$WORK/oracle_gcc.out"      > "$WORK/oracle_gcc.norm"
  norm_banner < "$WORK/oracle_upstream.out" > "$WORK/oracle_upstream.norm"
  # Positive control: the normaliser must actually have fired, or this comparison
  # silently becomes the un-normalised one it was written to replace.
  grep -q '^BusyBox vX (X) multi-call binary\.$' "$WORK/oracle_gcc.norm" \
    || die "the banner normaliser matched nothing -- either the banner format changed or these transcripts never print it, and in both cases this comparison is not the one it claims to be"
  if cmp -s "$WORK/oracle_gcc.norm" "$WORK/oracle_upstream.norm"; then
    printf '  ORACLE  %s agrees with the gcc unity\n' "$(basename "$UPSTREAM")"
  else
    printf '  FAIL    the two ORACLES disagree -- the unity is not equivalent to a real link\n'
    diff -a "$WORK/oracle_gcc.norm" "$WORK/oracle_upstream.norm" | head -20
    RC=1
  fi
else
  printf '  note    no separately-linked busybox in the tree; gcc unity is the only oracle\n'
fi

# ---- subjects ---------------------------------------------------------------
for t in $TARGETS; do
  out="$WORK/pxx_$t"
  if [ "$t" = "x86_64" ]; then targflag=""; runner=""
  else targflag="--target=$t"; runner="$ROOT/tools/run_target.sh $t"; fi

  if [ "$SEPARATE" -eq 1 ]; then
    if [ "$t" != "x86_64" ]; then
      printf '  note    %-8s skipped: --emit-obj has no object writer for this target\n' "$t"
      continue
    fi
    # One object per TU. Each gets the SAME preamble the unity's preamble
    # supplies, because busybox's real build force-includes include/autoconf.h
    # (Makefile.flags) and pxx has no -include -- so this is what
    # `gcc -include include/autoconf.h` does, spelled as source, not a dodge.
    sed -n '1,/^#include "libbb\/appletlib.c"$/p' "$CATUNITY" | sed '$d' > "$WORK/preamble.h"
    grep -q '^#include "include/autoconf.h"$' "$WORK/preamble.h" \
      || die "the unity preamble no longer includes autoconf.h -- every ENABLE_* would be undeclared and every applet would compile itself out"
    rm -rf "$WORK/obj" "$WORK/wrap"; mkdir -p "$WORK/obj" "$WORK/wrap"
    nobj=0; objfail=0
    # The unity's own include list, so this compiles EXACTLY the translation
    # units the unity does and the two builds stay comparable. appletlib is
    # added back: separate compilation has no ordering constraint to work
    # around, which is half the point of this mode.
    { printf '#include "libbb/appletlib.c"\n'; cat "$WORK/includes.txt"; } | while read -r inc; do
        printf '%s\n' "$inc" | sed 's|^#include "||; s|"$||'
      done > "$WORK/tulist.txt"
    while read -r src; do
      tag="$(printf '%s' "$src" | tr / _ | sed 's/\.c$//')"
      { cat "$WORK/preamble.h"; printf '#include "%s"\n' "$src"; } > "$WORK/wrap/$tag.c"
      if ( cd "$BB" && "$COMPILER" --emit-obj $INC "$WORK/wrap/$tag.c" "$WORK/obj/$tag.o" ) \
           >> "$WORK/build_$t.log" 2>&1; then
        nobj=$((nobj+1))
      else
        objfail=$((objfail+1))
        printf '  FAIL    %-8s %s did not become an object: %s\n' "$t" "$src" \
               "$(grep -E 'error:' "$WORK/build_$t.log" | tail -1)"
      fi
    done < "$WORK/tulist.txt"
    # A link over zero objects is the same silent success as a diff over zero
    # cases, so the count is asserted rather than printed.
    nobj=$(ls "$WORK/obj"/*.o 2>/dev/null | wc -l)
    [ "$nobj" -gt 1 ] || die "separate mode produced $nobj object(s) -- there is nothing here that a unity build would not also prove"
    if ! gcc -Wl,-z,muldefs -o "$out" "$WORK/obj"/*.o >> "$WORK/build_$t.log" 2>&1; then
      printf '  FAIL    %-8s %d objects did not link\n' "$t" "$nobj"
      grep -oE "undefined reference to \`[^']*'" "$WORK/build_$t.log" | sort -u | head -10
      RC=1; continue
    fi
    printf '  note    %-8s %d objects linked separately (%d bytes)\n' "$t" "$nobj" "$(stat -c%s "$out")"
  elif ! ( cd "$BB" && "$COMPILER" $targflag $INC "$UNITY" "$out" ) > "$WORK/build_$t.log" 2>&1; then
    printf '  FAIL    %-8s pxx could not build the unity\n' "$t"
    grep -v '^ok:' "$WORK/build_$t.log" | head -10
    RC=1; continue
  fi

  # An undefined-symbol import is a FAILURE here, not a warning to scroll past:
  # a busybox symbol crtl does not define means we emitted a reference gcc
  # folded away, and the binary dies before main with `symbol lookup error`.
  # It is also the exact shape rung 2 first broke on, so it gets a named check
  # rather than being left to whether some case happens to execute that path.
  if grep -q 'crtl does not define' "$WORK/build_$t.log"; then
    printf '  FAIL    %-8s emitted references gcc does not: %s\n' "$t" \
           "$(sed -n 's/.*crtl does not define \([^—]*\).*/\1/p' "$WORK/build_$t.log" | head -1)"
    RC=1; continue
  fi

  install_bin "$WORK/p_$t" "$out"
  # Per-case exit statuses are part of the compared OUTPUT (run_cases prints
  # them), so this call's own status carries no information and is ignored.
  run_cases "$runner" "$WORK/p_$t" > "$WORK/pxx_$t.out" 2>&1 || true

  if cmp -s "$WORK/oracle_gcc.out" "$WORK/pxx_$t.out"; then
    printf '  PASS    %-8s byte-identical to the gcc oracle over %d cases\n' \
           "$t" "$NCASES"
  else
    printf '  FAIL    %-8s differs from the gcc oracle\n' "$t"
    diff "$WORK/oracle_gcc.out" "$WORK/pxx_$t.out" | head -30
    RC=1
  fi
done

[ "$RC" -eq 0 ] && printf 'busybox-diff: GREEN\n' || printf 'busybox-diff: RED\n'
printf 'BUSYBOX-DIFF-COMPLETE\n'
exit "$RC"
