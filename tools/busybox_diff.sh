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
#   --dce       add --dce to each per-TU compile in --separate mode. OPT-IN, and a
#               measurement switch rather than a default: --dce under --emit-obj
#               roots the pass at the object's EXPORTED symbols, and a C object
#               exports the whole crtl runtime WEAK (which is what lets two
#               objects link at all), so the pass can only drop what no export
#               reaches. Measured on a 3-TU C program at 39c7042211a7: 624856 ->
#               336016 linked, and the cost of separate compilation 242568 ->
#               42176. Ignored outside --separate: there are no objects to prune.
#   --separate  build busybox the way BUSYBOX does -- one object per translation
#               unit and a real link -- instead of as a unity. x86_64 only,
#               because --emit-obj has no aarch64 object writer yet. This is a
#               STRICTLY STRONGER claim than the unity: it needs no include
#               ordering, no ASH_TEST exclusion, and no preamble tricks, so it
#               is the configuration that scales past the handful of applets a
#               unity can hold. It NO LONGER needs -Wl,-z,muldefs -- the link
#               at line ~1083 is a plain `gcc -o out obj/*.o'. Added in
#               3056e214c and REMOVED in 9e7c4cf8c -- the same commit that made
#               `static' emit LOCAL, which is what stopped the duplicate strong
#               definitions it was hiding; see
#               bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link.
#               CONSEQUENCE, measured 2026-09-02: --separate --pinned now FAILS
#               to link (v399, 954adef93a7b), on `multiple definition of abort,
#               abs, accept, ...' -- crtl's public surface, not the internals.
#               That is not a harness bug: the flag was dropped on the strength
#               of a compiler change, so a compiler from BELOW that change
#               cannot build this mode. A --separate size from an old compiler
#               is therefore not obtainable here, and any size compared across
#               that boundary is comparing two different link modes.
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
OBJFLAGS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pinned)  COMPILER="$ROOT/stable_linux_amd64/default/pinned"; shift ;;
    --keep)    KEEP=1; shift ;;
    --targets) TARGETS="$2"; shift 2 ;;
    --applets) APPLETS="$2"; shift 2 ;;
    --separate) SEPARATE=1; shift ;;
    --dce)     OBJFLAGS="--dce"; shift ;;
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
# Every applet-name lookup below is `grep -qxF' -- FIXED string, whole line.
# An applet name is not a regex and two of busybox's are not even close: `['
# and `[[' made `grep -q "^# CONFIG_$A is not set$"' exit with
# "grep: Unmatched [", and the caller read that nonzero as "this busybox does
# not have that applet" and said so. The conclusion happened to be harmless and
# the reasoning was not measurement at all -- the instrument had failed
# syntactically and still answered. Measured 2026-09-02 by feeding this script
# the host's full `busybox --list'.
configure_tree() {
  local log="$1" a
  printf 'busybox-diff: configuring %s for applets: %s\n' "$BB" "$APPLETS"
  (
    cd "$BB" || exit 1
    make allnoconfig >/dev/null 2>&1 || exit 1
    # Collect EVERY unmappable applet before giving up, rather than dying on
    # the first. The mapping here is a naive uppercase-and-underscore, and
    # busybox does not always agree with it -- `[' is CONFIG_TEST1, `sh' is
    # selected through SH_IS_*, several aliases live under a FEATURE_ knob of
    # the applet they alias. Exiting on the first one turns "which of these 274
    # names does this tree not know" into 274 sequential runs, each costing an
    # allnoconfig. The whole answer is in one pass over .config.
    unmapped=""
    for a in $APPLETS; do
      A=$(printf '%s' "$a" | tr 'a-z-' 'A-Z_')
      if grep -qxF "# CONFIG_$A is not set" .config; then
        sed -i "s/^# CONFIG_$A is not set\$/CONFIG_$A=y/" .config
      elif grep -qxF "CONFIG_$A=y" .config; then
        : # already on (allnoconfig left it on, or an earlier name selected it)
      else
        unmapped="$unmapped $a"
      fi
    done
    if [ -n "$unmapped" ]; then
      printf 'this busybox has no CONFIG_ symbol under the harness spelling for:%s\n' "$unmapped" >&2
      printf '(the mapping is uppercase-with-underscores; an applet whose knob is named differently -- `[` is CONFIG_TEST1, `sh` goes through SH_IS_*, aliases live under a FEATURE_ of the applet they alias -- has to be dropped from the list or spelled the way its Config.in spells it)\n' >&2
      exit 1
    fi
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
    # USE_BB_CRYPT: busybox's own DES/MD5/SHA crypt, instead of libcrypt's.
    # su/login/passwd/chpasswd/sulogin/mkpasswd call crypt(), and with this off
    # the LINK needs -lcrypt -- which the gcc oracle can be given and pxx cannot,
    # because lib/crtl has no crypt. Linking the two sides against different
    # libraries would make the comparison meaningless even where it passed, and
    # dropping six applets to avoid one symbol would shrink the corpus for no
    # reason. Turning it on makes BOTH sides self-contained and adds busybox's
    # own crypt sources to the C the frontend has to compile, which is the point
    # of the corpus. Measured 2026-09-02: at 257 applets `crypt' was the ONLY
    # undefined symbol in the gcc oracle's 400-object link.
    sed -i 's/^# CONFIG_USE_BB_CRYPT is not set$/CONFIG_USE_BB_CRYPT=y/' .config
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
# Which requested applets the configured tree does NOT have on. Prints them,
# one per line, so a failure can NAME the applet instead of only its count.
# `oldconfig' drops a knob whose dependencies are unmet, and it does so
# silently: asking for 141 applets and being handed 140 used to produce
# "reports #define NUM_APPLETS 140, not 141", which tells you that something
# was dropped and never which thing, so every diagnosis started with a manual
# bisect of the applet list. The information was always in .config.
missing_applets() {
  local a A
  [ -f "$BB/.config" ] || { printf '%s\n' $APPLETS; return 0; }
  for a in $APPLETS; do
    A="$(printf '%s' "$a" | tr 'a-z-' 'A-Z_')"
    grep -qxF "CONFIG_$A=y" "$BB/.config" || printf '%s\n' "$a"
  done
}

applets_ok() {
  local a A
  [ -f "$BB/.config" ] || return 1
  for a in $APPLETS; do
    A="$(printf '%s' "$a" | tr 'a-z-' 'A-Z_')"
    grep -qxF "CONFIG_$A=y" "$BB/.config" || return 1
  done
  # Nothing EXTRA needs no separate check: this asks that every requested
  # applet is on, and the NUM_APPLETS test beside it asks that the total is
  # exactly $NAPPLETS. All-present plus right-count is the exact set.
  return 0
}

# The applets this tree ACTUALLY builds, read out of the generated table rather
# than inferred from a count. NUM_APPLETS was a proxy and it is a lossy one:
# `busybox' is the multiplexer and has a CONFIG_ but no entry here, and an
# applet can have CONFIG_X=y and still produce no entry when every FEATURE_
# under it is off (measured: `tftp' with FEATURE_TFTP_GET/PUT both off). So a
# run asking for 259 names legitimately built 257 applets, and the count check
# called that "the tree has EXTRAS" -- a false sentence, in the direction that
# sends the reader looking for something that is not there. Read the table.
enabled_applets() {
  [ -f "$BB/include/applet_tables.h" ] || return 1
  awk '/^const char applet_names/,/^;/' "$BB/include/applet_tables.h" \
    | grep -oE '"[^"]+"' | tr -d '"' | grep -vx '\\0' | sed '/^$/d' | sort -u
}

# `busybox' is the multiplexer, not an applet entry -- comparing with it in
# reports a phantom missing applet on every multi-applet run.
requested_applets() { printf '%s\n' $APPLETS | grep -vx busybox | sort -u; }

# Does the built table hold exactly what was asked for? This replaces both the
# NUM_APPLETS equality and applets_ok: it answers the same question about the
# same population, by name and in both directions.
applet_table_matches() {
  local e r n num
  e="$(enabled_applets)" || return 1
  # POSITIVE CONTROL on our own reader before trusting its output: the table
  # says how many applets it holds, and if this extraction does not agree with
  # that number then it is not reading the table, and a diff built from it
  # would name the wrong applets with total confidence. (It did: the first
  # version of this counted the "\0" separator as an applet.)
  n=$(printf '%s\n' "$e" | grep -c .)
  num=$(sed -n 's/^#define NUM_APPLETS //p' "$BB/include/applet_tables.h" | tr -d '[:space:]')
  [ -n "$num" ] || return 1
  [ "$n" = "$num" ] || die "applet-table reader is broken: it found $n names where the table declares NUM_APPLETS $num. Every applet diagnosis below would be built on that, so this stops here rather than naming applets it cannot know."
  r="$(requested_applets)"
  [ "$e" = "$r" ]
}

# Knobs this harness turns on for EVERY run, independent of the applet list.
# They need their own staleness test: a tree configured before one of them was
# added has the right applets and the wrong build, and the applet comparison
# above cannot see that.
REQUIRED_ON="USE_BB_CRYPT"
required_knobs_ok() {
  local f
  [ -f "$BB/.config" ] || return 1
  for f in $REQUIRED_ON; do grep -qxF "CONFIG_$f=y" "$BB/.config" || return 1; done
  return 0
}

ash_features_ok() {
  local f
  printf '%s\n' $APPLETS | grep -qx ash || return 0
  [ -f "$BB/.config" ] || return 1
  for f in $ASH_ON;  do grep -qxF "CONFIG_$f=y" "$BB/.config" || return 1; done
  for f in $ASH_OFF; do grep -qxF "CONFIG_$f=y" "$BB/.config" && return 1; done
  return 0
}

if [ ! -f "$BB/include/applet_tables.h" ] \
   || ! applet_table_matches \
   || ! required_knobs_ok \
   || ! ash_features_ok \
   || ! grep -qx "$(printf '#define ENABLE_BUSYBOX %s' "$([ "$NAPPLETS" -gt 1 ] && echo 1 || echo 0)")" "$BB/include/autoconf.h"; then
  CFGLOG="${TMPDIR:-/tmp}/bbdiff-configure.log"
  # Report the FIRST compiler errors, not the last 20 lines. A configure that
  # dies inside busybox's own gcc build keeps going after the first failure, so
  # the tail is whatever compiled last -- measured 2026-09-02 with `tc' in the
  # applet list: the tail showed `AR libbb/lib.a' and three -Wunused-result
  # warnings while the actual cause, "networking/tc.c:236: error: TCA_CBQ_MAX
  # undeclared", sat at line 491 of 769. A diagnostic that prints the wrong end
  # of the log is worse than none: it looks like an answer.
  configure_tree "$CFGLOG" || {
    if grep -qE '(error:|Error [0-9])' "$CFGLOG"; then
      printf 'first errors in the configure log:\n' >&2
      grep -nE '(error:|Error [0-9])' "$CFGLOG" | head -8 >&2
      printf '(and the files they are in -- an applet whose sources do not build with the HOST gcc against THIS kernel'"'"'s headers has to come off the list; that is a busybox/host mismatch, not a pxx defect)\n' >&2
      printf 'files: %s\n' "$(grep -oE '^[A-Za-z0-9_./-]+\.[ch]:[0-9]+:[0-9]+: error:' "$CFGLOG" | cut -d: -f1 | sort -u | tr '\n' ' ')" >&2
    else
      tail -20 "$CFGLOG" >&2
    fi
    die "could not configure the tree (log: $CFGLOG)"
  }
  if ! applet_table_matches; then
    ABSENT="$(comm -23 <(requested_applets) <(enabled_applets) | tr '\n' ' ')"
    EXTRA="$(comm -13 <(requested_applets) <(enabled_applets) | tr '\n' ' ')"
    MSG="the configured tree does not build the applet set that was asked for."
    [ -n "${ABSENT# }" ] && MSG="$MSG ASKED FOR BUT NOT BUILT: ${ABSENT% } (unmet dependency; a knob spelled differently in Config.in; or CONFIG_X=y with every FEATURE_ under it off, which leaves the applet with no entry at all -- tftp is exactly that)."
    [ -n "${EXTRA# }" ] && MSG="$MSG BUILT BUT NOT ASKED FOR: ${EXTRA% } (selected as a dependency of something on the list)."
    die "$MSG (log: $CFGLOG)"
  fi
  rm -f "$CFGLOG"
fi

# `make oldconfig` resolves dependencies and will silently drop a knob whose
# deps are unmet, so asking for CONFIG_FEATURE_SH_MATH is not the same as
# getting it -- and the symptom would be a GREEN run over a stub shell.
# oldconfig resolves dependencies and drops what it cannot satisfy, so asking
# for a knob is not getting it -- and a dropped USE_BB_CRYPT comes back as an
# undefined `crypt' at LINK time, 400 objects later.
for f in $REQUIRED_ON; do
  grep -qxF "CONFIG_$f=y" "$BB/.config" \
    || die "oldconfig dropped CONFIG_$f -- without it the link needs -lcrypt, which the gcc oracle can be given and pxx cannot (lib/crtl has no crypt), so the two sides would not be the same program"
done

if printf '%s\n' $APPLETS | grep -qx ash; then
  for f in $ASH_ON; do
    grep -qxF "CONFIG_$f=y" "$BB/.config" \
      || die "oldconfig dropped CONFIG_$f -- the shell under test is not the one asked for (without FEATURE_SH_MATH, \$((arith)) is a syntax error and the whole comparison is over a stub)"
  done
  for f in $ASH_OFF; do
    grep -qxF "CONFIG_$f=y" "$BB/.config" \
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
cleanup() { rm -f "${CTEST:-}"; [ "$KEEP" -eq 1 ] && printf 'busybox-diff: work dir kept at %s\n' "$WORK" || rm -rf "$WORK"; }
trap cleanup EXIT

# The compiler under test is COPIED here and every build below runs the copy.
# A 265-TU run takes minutes, and `compiler/pascal26' is written IN PLACE by
# `make' -- so any other work in this tree (a rebuild, a `git stash', another
# agent's sync) swaps the binary underneath a run in flight. Nothing errors:
# the run finishes, and its own `sha256=' line then names a compiler that
# compiled only part of it. Measured 2026-09-02, on this script, by its own
# author rebuilding during a run. Pinning by PATH is not pinning.
# The snapshot lives BESIDE the original, not in $WORK: pxx derives two of its
# default crtl include roots from argv[0] (`<exe>/../lib/crtl/include' and one
# level above), and the builds below run with cwd = $BB, where the third root,
# the cwd-relative `lib/crtl/include/', does not exist. So a snapshot in /tmp
# has no crtl at all. Measured both ways from $BB: the copy beside the original
# compiles `#include <stdio.h>'; the copy in /tmp does not. From the repo root
# BOTH work, which is why this needed a control run from the cwd the harness
# actually uses rather than from the one that was convenient.
CTEST="$ROOT/compiler/.pxx-under-test-$$"
cp "$COMPILER" "$CTEST" || die "could not snapshot the compiler under test"
CSHA="$(sha256sum "$CTEST" | cut -d' ' -f1)"
[ -n "$CSHA" ] || die "could not hash the compiler snapshot"
COMPILER="$CTEST"

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

gen_includes() {   # archive members -> #include lines, appletlib/crt* removed
  # THE MEMBER'S DIRECTORY IS PART OF ITS IDENTITY. The map names members as
  # `libbb/lib.a(uuencode.o)', and an earlier cut of this took the BASENAME and
  # went looking for `uuencode.c' with find. Six basenames exist twice in this
  # tree (common.c login.c printenv.c ssl_helper.c time.c uuencode.c), so the
  # sort|head -1 picked `coreutils/uuencode.c' deterministically, dropped
  # `libbb/uuencode.c' entirely, and the dedupe by basename hid that two
  # members had collapsed into one. It failed the only way this class fails:
  # silently, and then as `undefined reference to bb_uuencode' at link time,
  # in GCC's OWN build -- a name standing in for the thing it names.
  local mem src n
  grep -oE '[a-zA-Z0-9_/.+-]+\.a\([a-z_0-9]+\.o\)' "$MAP" | sort -u \
    | sed 's|/lib\.a(|/|; s|\.o)$|.c|' \
    | grep -vE '/(crtbegin|crtend|crti|crtn|appletlib)\.c$' \
    | while read -r src; do
        [ -f "$BB/$src" ] || { printf 'archive member maps to %s, which is not a file\n' "$src" >&2; return 1; }
        printf '#include "%s"\n' "$src"
      done
}

gen_includes > "$WORK/includes.txt.raw" || die "could not map every archive member to a source file"
[ -s "$WORK/includes.txt.raw" ] || die "the map yielded no archive members -- refusing to build an empty unity"
# The list must ACCOUNT FOR every archive member the tree's own link used. A
# generator that silently merges two members produces a shorter list and a
# build that is missing a translation unit, which shows up much later as an
# undefined reference blaming an applet that did nothing wrong.
nmem=$(grep -oE '[a-zA-Z0-9_/.+-]+\.a\([a-z_0-9]+\.o\)' "$MAP" | sort -u \
       | sed 's|/lib\.a(|/|; s|\.o)$|.c|' \
       | grep -vcE '/(crtbegin|crtend|crti|crtn|appletlib)\.c$')
ninc=$(wc -l < "$WORK/includes.txt.raw")
[ "$nmem" -eq "$ninc" ] || die "the map has $nmem archive members but the include list has $ninc entries -- some member was dropped or merged, and the build below would be missing a translation unit"

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
  #
  # UNITY MODE ONLY. The message has always ended "separate compilation is the
  # fix", and once that mode existed the guard was still refusing the exact
  # combination the fix makes legal -- a true statement about the unity, obeyed
  # by tooling in a mode it was not about. Under --separate each file is its own
  # translation unit and neither can reach the other's macros.
  if [ "$SEPARATE" -eq 0 ] && grep -q '^#include "coreutils/test.c"$' "$WORK/includes.txt"; then
    die "coreutils/test.c and shell/ash.c both claim ordinary identifiers via globals macros and collide in BOTH include orders -- this unity cannot contain both. Separate compilation is the fix (--separate); turning ASH_TEST back on is not."
  fi
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
printf 'busybox-diff: compiler=%s (snapshot of %s/compiler/pascal26)\n' "$COMPILER" "$ROOT"
printf 'busybox-diff: sha256=%s\n' "$CSHA"
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
  # `busybox' is skipped: it is already there as the REAL binary, and
  # `ln -sf busybox $1/busybox' replaces it with a symlink to itself. Every
  # other applet then resolves through that loop, so the whole run dies with
  # "Too many levels of symbolic links" on every case -- 595 of them, measured
  # 2026-09-02, the first time an applet list contained the multiplexer's own
  # name. The self-link is the one input this loop cannot be given.
  for a in $APPLETS; do
    [ "$a" = busybox ] && continue
    ln -sf busybox "$1/$a"
  done
  # Positive control: the thing every symlink points at has to be the binary.
  # A test for "the symlinks exist" passes on the broken layout.
  [ -f "$1/busybox" ] && [ ! -L "$1/busybox" ] && [ -x "$1/busybox" ] \
    || die "install_bin left $1/busybox as something other than the real executable"
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


# The coreutils half of a userland. Same two constraints as the ash cases and
# for the same reasons, plus one more that is specific to file tools:
#
#   EVERYTHING RUNS UNDER $D, WHICH IS SHARED. The oracle and each subject are
#   installed in DIFFERENT directories ($WORK/g vs $WORK/p_<target>), so any
#   path a tool prints from its own install dir would diff on every row for a
#   reason that is not a defect. $D is one directory used by both, so an error
#   message naming a path is comparable -- and error messages are half of what
#   is being compared here, since that is where errno reaches the output.
#
#   NOTHING THAT CARRIES A TIMESTAMP, a uid, or a device number: no `cp -a`,
#   no `-p`, no mtime-sensitive flag. Two builds of the same program disagree
#   on none of those, but two RUNS do.
#
# The scratch tree is rebuilt per run, so a row never sees the previous run's
# leftovers and the cases can be read in any order.
run_coreutils_cases() {   # $1 = runner, $2 = install dir
  local runner="$1" dir="$2" c="$D/cu"
  rm -rf "$c"; mkdir -p "$c"
  printf 'alpha\nbeta\ngamma\n' > "$c/three.txt"
  printf 'no-trailing-newline' > "$c/nonl.txt"

  if has_applet pwd; then
    printf '### pwd\n'
    ( cd "$c" && run_one "$runner" "$dir/pwd" ); printf '### exit=%d\n' "$?"
  fi
  if has_applet mkdir; then
    for a in "$c/d1" "-p $c/d2/d3/d4" "$c/d1" "-p $c/d1" "$c/nope/deep"; do
      printf '### mkdir [%s]\n' "$a"; run_one "$runner" "$dir/mkdir" $a; printf '### exit=%d\n' "$?"
    done
  fi
  if has_applet wc; then
    for a in "$c/three.txt" "-l $c/three.txt" "-w $c/three.txt" "-c $c/three.txt" \
             "$c/three.txt $c/nonl.txt" "$c/missing.txt"; do
      printf '### wc [%s]\n' "$a"; run_one "$runner" "$dir/wc" $a; printf '### exit=%d\n' "$?"
    done
  fi
  if has_applet head; then
    for a in "$c/three.txt" "-n 2 $c/three.txt" "-n 0 $c/three.txt" "-n 99 $c/three.txt" \
             "$c/missing.txt"; do
      printf '### head [%s]\n' "$a"; run_one "$runner" "$dir/head" $a; printf '### exit=%d\n' "$?"
    done
  fi
  if has_applet cp; then
    printf '### cp file\n';    run_one "$runner" "$dir/cp" "$c/three.txt" "$c/copy.txt"; printf '### exit=%d\n' "$?"
    printf '### cp missing\n'; run_one "$runner" "$dir/cp" "$c/missing.txt" "$c/x.txt";  printf '### exit=%d\n' "$?"
    printf '### cp -r\n';      run_one "$runner" "$dir/cp" -r "$c/d2" "$c/d2copy";       printf '### exit=%d\n' "$?"
  fi
  if has_applet mv; then
    printf '### mv file\n';    run_one "$runner" "$dir/mv" "$c/copy.txt" "$c/moved.txt"; printf '### exit=%d\n' "$?"
    printf '### mv missing\n'; run_one "$runner" "$dir/mv" "$c/missing.txt" "$c/y.txt";  printf '### exit=%d\n' "$?"
  fi
  if has_applet printf; then
    for a in '%s|%d|%x\n str 42 255' '%5s|%-5s|%05d\n r l 42' '%c%c\n A B' 'plain\n'; do
      printf '### printf [%s]\n' "$a"; run_one "$runner" "$dir/printf" $a; printf '### exit=%d\n' "$?"
    done
  fi
  if has_applet rm; then
    printf '### rm file\n';    run_one "$runner" "$dir/rm" "$c/moved.txt";     printf '### exit=%d\n' "$?"
    printf '### rm missing\n'; run_one "$runner" "$dir/rm" "$c/missing.txt";   printf '### exit=%d\n' "$?"
    printf '### rm -f\n';      run_one "$runner" "$dir/rm" -f "$c/missing.txt"; printf '### exit=%d\n' "$?"
    printf '### rm dir\n';     run_one "$runner" "$dir/rm" "$c/d1";            printf '### exit=%d\n' "$?"
    printf '### rm -rf\n';     run_one "$runner" "$dir/rm" -rf "$c/d2";        printf '### exit=%d\n' "$?"
  fi
  if has_applet sleep; then
    printf '### sleep 0\n';   run_one "$runner" "$dir/sleep" 0;    printf '### exit=%d\n' "$?"
    printf '### sleep bad\n'; run_one "$runner" "$dir/sleep" zzz;  printf '### exit=%d\n' "$?"
  fi
  if has_applet sort; then
    printf 'delta\nalpha\ncharlie\nbravo\nalpha\n' > "$c/uns.txt"
    printf '10\n9\n100\n1\n' > "$c/nums.txt"
    for a in "$c/uns.txt" "-r $c/uns.txt" "-u $c/uns.txt" "-n $c/nums.txt" "$c/missing.txt"; do
      printf '### sort [%s]\n' "$a"; run_one "$runner" "$dir/sort" $a; printf '### exit=%d\n' "$?"
    done
  fi
  if has_applet touch; then
    # Timestamps are never PRINTED here -- the resulting-tree row is what shows
    # the file was created, so this stays deterministic across two runs.
    printf '### touch new\n';     run_one "$runner" "$dir/touch" "$c/touched"; printf '### exit=%d\n' "$?"
    printf '### touch existing\n';run_one "$runner" "$dir/touch" "$c/three.txt"; printf '### exit=%d\n' "$?"
    printf '### touch nodir\n';   run_one "$runner" "$dir/touch" "$c/nope/x"; printf '### exit=%d\n' "$?"
  fi
  if has_applet chmod; then
    printf '### chmod ok\n';      run_one "$runner" "$dir/chmod" 0644 "$c/three.txt"; printf '### exit=%d\n' "$?"
    printf '### chmod symbolic\n';run_one "$runner" "$dir/chmod" a-w "$c/three.txt"; printf '### exit=%d\n' "$?"
    printf '### chmod missing\n'; run_one "$runner" "$dir/chmod" 0644 "$c/missing.txt"; printf '### exit=%d\n' "$?"
    run_one "$runner" "$dir/chmod" 0644 "$c/three.txt" >/dev/null 2>&1   # leave it writable for rm
  fi
  if has_applet ln; then
    printf '### ln -s\n';       run_one "$runner" "$dir/ln" -s three.txt "$c/link1"; printf '### exit=%d\n' "$?"
    printf '### ln hard\n';     run_one "$runner" "$dir/ln" "$c/three.txt" "$c/link2"; printf '### exit=%d\n' "$?"
    printf '### ln exists\n';   run_one "$runner" "$dir/ln" -s three.txt "$c/link1"; printf '### exit=%d\n' "$?"
    printf '### ln missing\n';  run_one "$runner" "$dir/ln" "$c/missing.txt" "$c/link3"; printf '### exit=%d\n' "$?"
  fi
  # The tree that is LEFT is part of the comparison: it catches a tool that
  # reported success and did nothing, which every row above would miss.
  printf '### resulting tree\n'
  ( cd "$c" && find . | sort )
  printf '### exit=%d\n' "$?"
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
  run_coreutils_cases "$runner" "$dir"
  return 0
}

RC=0

make_wrappers() {
  # One wrapper .c per translation unit, each carrying the SAME preamble the
  # unity's preamble supplies -- busybox's real build force-includes
  # include/autoconf.h (Makefile.flags) and pxx has no -include, so this is
  # what `gcc -include include/autoconf.h` does, spelled as source.
  #
  # BUILT ONCE AND SHARED BY BOTH SIDES. Now that the oracle also compiles
  # separately, pxx and gcc must be handed the SAME translation units, or the
  # comparison is between two different programs rather than two compilers.
  sed -n '1,/^#include "libbb\/appletlib.c"$/p' "$CATUNITY" | sed '$d' > "$WORK/preamble.h"
  grep -q '^#include "include/autoconf.h"$' "$WORK/preamble.h" \
    || die "the unity preamble no longer includes autoconf.h -- every ENABLE_* would be undeclared and every applet would compile itself out"
  # The unity's own include list, so this compiles EXACTLY the translation
  # units the unity does. appletlib is added back: separate compilation has no
  # ordering constraint to work around, which is half the point of this mode.
  { printf '#include "libbb/appletlib.c"\n'; cat "$WORK/includes.txt"; } | while read -r inc; do
      printf '%s\n' "$inc" | sed 's|^#include "||; s|"$||'
    done > "$WORK/tulist.txt"
  [ -s "$WORK/tulist.txt" ] || die "the translation-unit list is empty -- there is nothing to compile separately"
  rm -rf "$WORK/wrap"; mkdir -p "$WORK/wrap"
  while read -r src; do
    tag="$(printf '%s' "$src" | tr / _ | sed 's/\.c$//')"
    { cat "$WORK/preamble.h"; printf '#include "%s"\n' "$src"; } > "$WORK/wrap/$tag.c"
  done < "$WORK/tulist.txt"
}

# -std=gnu99 because BUSYBOX SAYS SO. Its own Makefile.flags carries
# `CPPFLAGS += $(call cc-option,-std=gnu99,)', so every object in the tree's own
# build is compiled that way, and an oracle that uses the compiler's default
# standard is not building the same program. On a modern gcc the default is C23,
# where `nullptr' is a keyword: miscutils/bc.c uses it as an ORDINARY IDENTIFIER
# and the oracle refused the file ("expected identifier or `(' before
# `nullptr'") while busybox's own build of the identical source succeeded during
# configure, three minutes earlier in the same run. Measured 2026-09-02 at 257
# applets. This is not relaxing the oracle to let a subject pass -- pxx never
# saw the file, and the fix is to compile the program the way the program says
# it must be compiled.
command -v gcc >/dev/null 2>&1 || die "gcc is the oracle and is not installed"

if [ "$SEPARATE" -eq 1 ]; then
  # ---- oracle: gcc, ALSO SEPARATELY ------------------------------------------
  # THE UNITY CANNOT BE THIS MODE'S ORACLE PAST ABOUT 26 APPLETS, and the reason
  # is gcc's rather than pxx's: busybox's `struct globals` pattern is one
  # namespace claim per applet, so a wide unity does not compile for ANYONE.
  # Keeping a unity oracle would therefore cap separate compilation at the
  # unity's ceiling -- the exact ceiling this mode exists to remove. Both sides
  # now build the same wrappers the same way and only the compiler differs,
  # which is what the comparison was always about.
  make_wrappers
  rm -rf "$WORK/objg"; mkdir -p "$WORK/objg"
  while read -r src; do
    tag="$(printf '%s' "$src" | tr / _ | sed 's/\.c$//')"
    ( cd "$BB" && gcc -w -O2 -std=gnu99 -D_GNU_SOURCE -DBB_VER="\"$BBVER\"" $INC \
        -c "$WORK/wrap/$tag.c" -o "$WORK/objg/$tag.o" ) >> "$WORK/oracle_sep.log" 2>&1 \
      || die "gcc could NOT compile $src separately -- no oracle, so no result. See $WORK/oracle_sep.log"
  done < "$WORK/tulist.txt"
  ngobj=$(ls "$WORK/objg"/*.o 2>/dev/null | wc -l)
  [ "$ngobj" -gt 1 ] || die "the gcc oracle produced $ngobj object(s) -- nothing here that a unity build would not also prove"
  gcc -o "$WORK/oracle_gcc" "$WORK/objg"/*.o >> "$WORK/oracle_sep.log" 2>&1 \
    || die "the gcc oracle's $ngobj objects did not link -- see $WORK/oracle_sep.log"
  ORACLE_KIND="gcc separate build, $ngobj objects ("
else
  # ---- oracle: gcc on the same unity ----------------------------------------
  ( cd "$BB" && gcc -w -O2 -std=gnu99 -D_GNU_SOURCE -DBB_VER="\"$BBVER\"" $INC -o "$WORK/oracle_gcc" "$UNITY" ) \
    || die "gcc could NOT build the unity -- no oracle, so no result"
  ORACLE_KIND="gcc unity build ("
fi
install_bin "$WORK/g" "$WORK/oracle_gcc"
run_cases "" "$WORK/g" > "$WORK/oracle_gcc.out" 2>&1
NCASES="$(count_cases "$WORK/oracle_gcc.out")"
# A comparison over zero cases is the failure this whole script is shaped
# against: cmp of two empty transcripts is GREEN and means nothing. The count
# is load-bearing, so it is asserted rather than merely printed.
[ "$NCASES" -gt 0 ] || die "the oracle transcript holds no cases -- a byte-identical result over nothing is not a result"
printf '  ORACLE  %s%d cases)\n' "$ORACLE_KIND" "$NCASES"

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
    printf '  ORACLE  %s agrees with the gcc build\n' "$(basename "$UPSTREAM")"
  else
    printf '  FAIL    the two ORACLES disagree -- our gcc build is not equivalent to upstream'"'"'s\n'
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
    rm -rf "$WORK/obj"; mkdir -p "$WORK/obj" "$WORK/tu"
    nobj=0; objfail=0
    while read -r src; do
      tag="$(printf '%s' "$src" | tr / _ | sed 's/\.c$//')"
      # Each compile gets its OWN log, and the shared one is built by appending
      # them. The previous version compiled into the shared log and reported
      # `grep error: | tail -1' over the whole thing -- which is not this file's
      # error, it is the most recent error ANY file produced, and it silently
      # becomes a previous file's error the moment this compile's message is not
      # matched. Measured 2026-09-02 at 400 TUs: six FAIL lines (httpd.c,
      # telnetd.c, tls_sp_c32.c, dhcpc.c, fallocate.c, switch_root.c) all carried
      # bc.c's `zbc_parse_stmt_allow_NLINE_before' error, and the four real
      # causes (inline asm, a >256-byte local string array, statfs, tcsetpgrp)
      # appeared nowhere against a filename. Reading that report, you fix bc.c
      # seven times.
      if ( cd "$BB" && "$COMPILER" --emit-obj $OBJFLAGS $INC "$WORK/wrap/$tag.c" "$WORK/obj/$tag.o" ) \
           > "$WORK/tu/$tag.log" 2>&1; then
        nobj=$((nobj+1))
      else
        objfail=$((objfail+1))
        # -a because a build log holds compiler output and one bad byte makes
        # grep answer `binary file matches' and print nothing -- the same loud
        # failure that looks like a result as in the link block below.
        why="$(grep -a -E 'error:' "$WORK/tu/$tag.log" | head -1)"
        # An empty `why' is a REPORT, not a blank: a compile that failed without
        # an error: line means the compiler died some other way (a signal, an
        # assertion), and printing nothing after the colon reads as if the tool
        # had nothing to say rather than as the finding it is.
        [ -n "$why" ] || why="(no error: line -- exit was nonzero, see $WORK/tu/$tag.log)"
        printf '  FAIL    %-8s %s did not become an object: %s\n' "$t" "$src" "$why"
      fi
      cat "$WORK/tu/$tag.log" >> "$WORK/build_$t.log"
    done < "$WORK/tulist.txt"
    # A link over zero objects is the same silent success as a diff over zero
    # cases, so the count is asserted rather than printed.
    nobj=$(ls "$WORK/obj"/*.o 2>/dev/null | wc -l)
    [ "$nobj" -gt 1 ] || die "separate mode produced $nobj object(s) -- there is nothing here that a unity build would not also prove"
    if ! gcc -o "$out" "$WORK/obj"/*.o >> "$WORK/build_$t.log" 2>&1; then
      printf '  FAIL    %-8s %d objects did not link\n' "$t" "$nobj"
      # Two failure modes, not one. Grepping only for `undefined reference'
      # printed NOTHING for a link that died on multiple definitions -- the
      # exact failure -Wl,-z,muldefs used to hide -- so the report said the
      # link failed and refused to say why. A diagnostic that is silent on
      # half its population is the half you are about to spend an hour on.
      # -a on every one of these, for the same reason the transcript diff below
      # takes it: a build log holds compiler output, and one bad byte anywhere
      # in it makes grep answer "binary file matches" and print NOTHING. That is
      # not a silent failure -- it is a LOUD one that looks like a result, and it
      # printed exactly that for a 387-object link, twice, in place of the symbol
      # list this block exists to produce. Measured 2026-09-02.
      grep -a -oE "undefined reference to \`[^']*'" "$WORK/build_$t.log" | sort -u | head -10
      grep -a -oE "multiple definition of \`[^']*'" "$WORK/build_$t.log" | sort -u | head -10
      grep -a -E "^[^ ].*: (error|fatal)" "$WORK/build_$t.log" | sort -u | head -5
      RC=1; continue
    fi
    # The FLAGS are printed beside the size because this number is what the
    # crtl-per-object ticket is ranked on and `--dce' moves it by a factor. A
    # size reported without the flags that produced it is not comparable to the
    # next one anybody takes.
    printf '  note    %-8s %d objects linked separately (%d bytes, per-TU flags: --emit-obj%s)\n' \
      "$t" "$nobj" "$(stat -c%s "$out")" "${OBJFLAGS:+ $OBJFLAGS}"
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
    # -a, like the oracle-vs-upstream diff above: a `cat bin.dat` case puts
    # NUL bytes in both transcripts, and without it this prints
    # "Binary files ... differ" and no divergence at all -- a FAIL you cannot
    # read is barely better than no FAIL.
    diff -a "$WORK/oracle_gcc.out" "$WORK/pxx_$t.out" | head -30
    RC=1
  fi
done

[ "$RC" -eq 0 ] && printf 'busybox-diff: GREEN\n' || printf 'busybox-diff: RED\n'
printf 'BUSYBOX-DIFF-COMPLETE\n'
exit "$RC"
