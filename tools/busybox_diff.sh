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

while [ $# -gt 0 ]; do
  case "$1" in
    --pinned)  COMPILER="$ROOT/stable_linux_amd64/default/pinned"; shift ;;
    --keep)    KEEP=1; shift ;;
    --targets) TARGETS="$2"; shift 2 ;;
    --applets) APPLETS="$2"; shift 2 ;;
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
    yes '' | make oldconfig >/dev/null 2>&1 || exit 1
    make -j"$(nproc 2>/dev/null || echo 4)"
  ) > "$log" 2>&1
}

want_num_applets() { printf '#define NUM_APPLETS %s\n' "$NAPPLETS"; }

if [ ! -f "$BB/include/NUM_APPLETS.h" ] \
   || ! grep -qx "$(want_num_applets)" "$BB/include/NUM_APPLETS.h" \
   || ! grep -qx "$(printf '#define ENABLE_BUSYBOX %s' "$([ "$NAPPLETS" -gt 1 ] && echo 1 || echo 0)")" "$BB/include/autoconf.h"; then
  CFGLOG="${TMPDIR:-/tmp}/bbdiff-configure.log"
  configure_tree "$CFGLOG" || { tail -20 "$CFGLOG" >&2; die "could not configure the tree (log: $CFGLOG)"; }
  grep -qx "$(want_num_applets)" "$BB/include/NUM_APPLETS.h" \
    || die "configured tree reports $(tr -d '\n' < "$BB/include/NUM_APPLETS.h"), not $NAPPLETS applet(s) (log: $CFGLOG)"
  rm -f "$CFGLOG"
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

gen_includes > "$WORK/includes.txt" || die "could not map every archive member to a source file"
[ -s "$WORK/includes.txt" ] || die "the map yielded no archive members -- refusing to build an empty unity"
cat "$WORK/includes.txt" >> "$UNITY"

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

run_cases() {   # $1 = runner, $2 = install dir
  local runner="$1" dir="$2"
  if [ "$NAPPLETS" -eq 1 ]; then
    run_cat_cases "$runner" "$dir/busybox"
    return
  fi
  run_dispatch_cases "$runner" "$dir"
  has_applet cat  && run_cat_cases  "$runner" "$dir/cat"
  has_applet echo && run_echo_cases "$runner" "$dir"
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

# ---- subjects ---------------------------------------------------------------
for t in $TARGETS; do
  out="$WORK/pxx_$t"
  if [ "$t" = "x86_64" ]; then targflag=""; runner=""
  else targflag="--target=$t"; runner="$ROOT/tools/run_target.sh $t"; fi

  if ! ( cd "$BB" && "$COMPILER" $targflag $INC "$UNITY" "$out" ) > "$WORK/build_$t.log" 2>&1; then
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
