#!/bin/sh
# Build and refresh the FPC TRUNK oracle at ~/src/fpc-trunk.
#
# Owner ruled option B on 2026-09-01 (decide-where-a-persistent-fpc-trunk-oracle-lives):
# a build under ~, refreshed ON REQUEST by this script. Refresh is manual by
# design -- "it's quite rare that we test against a nightly build" -- and
# CLAUDE.md forbids timed callbacks, so nothing here schedules itself.
#
# Usage:
#   tools/fpc_trunk.sh            build if missing, else refresh to the upstream tip
#   tools/fpc_trunk.sh --path     print the compiler path (build if missing); nothing else on stdout
#   tools/fpc_trunk.sh --check    report how stale it is; exit 1 if absent, 2 if behind
#
# Then:  FPC_TRUNK="$(tools/fpc_trunk.sh --path) -Fu<rtl units>" tools/fpc_diff_probe.sh ...
#
# THREE TRAPS, measured 2026-08-16, encoded here so nobody rediscovers them:
#  1. `make -C rtl FPC=<new>` silently builds the RTL with the INSTALLED compiler.
#     The only symptom is `PPU Invalid Version 207 expecting 208` at USE time,
#     long after the build said OK. The rtl makefile wants PP=, not FPC=.
#  2. Whole-tree `make compiler` fails in utils_all with "Can't find unit system".
#     `make -C compiler ppcx64` is all an oracle needs.
#  4. `make -C compiler` builds the RTL with the SEED first (it needs one), so a
#     later `make -C rtl PP=<new>` is a NO-OP -- newer units, nothing to do,
#     exit 0 -- and you keep seed-built units whose symptom is trap 1's symptom.
#     `make -C rtl clean` first. Not in the recipe; found 2026-09-01 by running it.
#  3. Read the remote tip with %cd, NOT %ad. FPC trunk showed author date
#     2025-01-23 against commit date 2026-08-15; trusting %ad is what produced a
#     wrong "no fix found in trunk" conclusion off a 247-commit-stale mirror.
set -eu

TRUNK="${FPC_TRUNK_DIR:-$HOME/src/fpc-trunk}"
SEED="${FPC_SEED:-/usr/bin/ppcx64}"
MIRROR="$HOME/src/fpc-source"          # the owner's checkout: clone FROM it, never build IN it
GL=https://gitlab.com/freepascal.org/fpc/source.git
UNITS="$TRUNK/rtl/units/x86_64-linux"
PPC="$TRUNK/compiler/ppcx64"
mode="${1:-build}"

say() { [ "$mode" = --path ] || echo "$@" >&2; }

remote_tip() {  # %cd, never %ad -- trap 3
  git -C "$TRUNK" log -1 --format='%H %cd' --date=short gl/main 2>/dev/null
}

if [ "$mode" = --check ]; then
  [ -x "$PPC" ] || { echo "fpc-trunk: ABSENT ($TRUNK)"; exit 1; }
  git -C "$TRUNK" fetch --depth=200 -q gl main 2>/dev/null || true
  have=$(git -C "$TRUNK" rev-parse HEAD)
  want=$(git -C "$TRUNK" rev-parse gl/main 2>/dev/null || echo "$have")
  echo "fpc-trunk: $("$PPC" -iV) at ${have%${have#????????????}}  built $(date -r "$PPC" +%F)"
  [ "$have" = "$want" ] && { echo "fpc-trunk: CURRENT with gl/main"; exit 0; }
  echo "fpc-trunk: BEHIND gl/main by $(git -C "$TRUNK" rev-list --count HEAD..gl/main) commit(s) -- re-run without --check"
  exit 2
fi

if [ ! -d "$TRUNK/.git" ]; then
  say "fpc-trunk: creating $TRUNK (~4 min, ~1GB)"
  mkdir -p "$(dirname "$TRUNK")"
  if [ -d "$MIRROR/.git" ]; then
    # -s shares objects with the owner's checkout: fast, and never moves its HEAD.
    say "fpc-trunk: cloning from the local mirror $MIRROR"
    git clone -s -n -q "$MIRROR" "$TRUNK"
    git -C "$TRUNK" remote add gl "$GL"
  else
    # 2026-09-01: the recipe in decide-where-a-persistent-fpc-trunk-oracle-lives
    # names ~/src/fpc-source as "the user's checkout". It does not exist -- ~/src
    # did not exist at all. Do not restore that line without looking.
    say "fpc-trunk: no local mirror at $MIRROR -- shallow-cloning from GitLab"
    git init -q "$TRUNK"
    git -C "$TRUNK" remote add gl "$GL"
  fi
fi

say "fpc-trunk: fetching gl/main"
git -C "$TRUNK" fetch --depth=200 -q gl main
before=$(git -C "$TRUNK" rev-parse HEAD 2>/dev/null || echo none)
git -C "$TRUNK" checkout -q --detach gl/main
after=$(git -C "$TRUNK" rev-parse HEAD)
say "fpc-trunk: tip $(remote_tip)"

if [ "$before" != "$after" ] || [ ! -x "$PPC" ]; then
  say "fpc-trunk: building compiler (trap 2: -C compiler only, never whole-tree)"
  make -C "$TRUNK/compiler" -j"$(nproc)" ppcx64 FPC="$SEED" >/dev/null
  # TRAP 4, found 2026-09-01 and NOT in the recipe the ticket recorded:
  # `make -C compiler` builds the RTL WITH THE SEED, because it needs an RTL to
  # compile the compiler. The units are then newer than their sources, so the
  # rebuild below is a make NO-OP -- it prints nothing, exits 0, and leaves
  # seed-built units in place. The symptom is trap 1's symptom exactly
  # (`PPU Invalid Version 207 expecting 208`), which sends you looking at PP= vs
  # FPC= when PP= was already right. The clean is the fix.
  say "fpc-trunk: cleaning rtl (trap 4: compiler build left SEED-built units here)"
  make -C "$TRUNK/rtl" clean >/dev/null 2>&1 || true
  say "fpc-trunk: building rtl (trap 1: PP=, not FPC=)"
  make -C "$TRUNK/rtl" -j"$(nproc)" PP="$PPC" >/dev/null
else
  say "fpc-trunk: already at the tip, not rebuilding"
fi

# --- positive controls. Both CAN fail; that is the point. ---
v=$("$PPC" -iV)
case "$v" in
  3.2.2|"") echo "fpc-trunk: FAIL -- built compiler reports $v, which is the SEED's version." >&2
            echo "  A trunk build that answers 3.2.2 means the seed was used and nothing new exists." >&2
            exit 1;;
esac
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
printf 'begin WriteLn(42) end.\n' > "$t/p.pas"
# Keep the COMPILER's chatter out of the PROGRAM's output. Folding both into one
# variable with 2>&1 makes the comparison answer about the banner as well as the
# program, and it reports FAIL on a build that worked. (Done here 2026-09-01.)
if ! "$PPC" -Fu"$UNITS" -FE"$t" "$t/p.pas" >"$t/cc.log" 2>&1; then
  echo "fpc-trunk: FAIL -- trunk compiler cannot build a hello-world:" >&2
  tail -5 "$t/cc.log" >&2
  echo "  'PPU Invalid Version' here means the RTL was built with the seed (trap 1/4)." >&2
  exit 1
fi
out=$("$t/p") || { echo "fpc-trunk: FAIL -- compiled, but the program did not run" >&2; exit 1; }
[ "$out" = "42" ] || { echo "fpc-trunk: FAIL -- ran but printed '$out', not 42" >&2; exit 1; }

if [ "$mode" = --path ]; then echo "$PPC"; else
  say "fpc-trunk: OK -- FPC $v, verified by compiling and RUNNING a program"
  say ""
  say "  FPC_TRUNK=\"$PPC -Fu$UNITS\" tools/fpc_diff_probe.sh ..."
fi
