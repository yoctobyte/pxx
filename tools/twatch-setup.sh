#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Track T watcher box setup check (feature-track-t-watcher).
#
# Verifies a box can run tools/twatch.py at full tier and prints exactly
# what's missing (with apt hints). Read-only by default; --fetch-corpus
# additionally pulls the gitignored third-party trees.
#
# Deploy one-liner on a fresh box (the clone dir is the watcher's OWN —
# never a dev/agent checkout; twatch pauses on any tracked local change):
#   git clone git@github.com:yoctobyte/pxx.git ~/trackt-watch \
#     && ~/trackt-watch/tools/twatch-setup.sh --fetch-corpus \
#     && nohup ~/trackt-watch/tools/twatch.py --clone ~/trackt-watch >> ~/trackt-watch.log 2>&1 &
#
# Exit 0 = full tier capable; 1 = something missing (message says what, and
# which reduced tier still works).
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
missing=0; cross_ok=1; corpus_ok=1; sysroot_ok=1

say()  { printf '%s\n' "$*"; }
# PRESENT AND NON-EMPTY. `[ -d ]` alone calls an empty directory a fetched
# corpus, and an empty corpus does not fail -- it SKIPS, which scores passlike.
# `test-fgl` lived inside test-core guarded on /usr/share/fpcsrc, printed
# "SKIP (no fpcsrc)" and PASSED FOR ITS ENTIRE LIFE without running once. A skip
# is not an absence of information; it is a positive claim that nothing was
# found, so the check has to be able to tell an absent tree from a hollow one.
have_tree() { [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; }
need() { # need <cmd> <severity:hard|cross|nice> <apt hint>
  if command -v "$1" >/dev/null 2>&1; then
    say "  ok       $1"
  else
    case "$2" in
      hard)  say "  MISSING  $1  (required; apt install $3)"; missing=1 ;;
      cross) say "  missing  $1  (cross jobs go RED without it; apt install $3)"; cross_ok=0 ;;
      nice)  say "  missing  $1  ($4; apt install $3)" ;;
    esac
  fi
}

say "== twatch setup check ($ROOT) =="
say "-- required --"
need python3 hard python3
need make    hard make
need git     hard git
need cc      hard gcc "" # cc: zlib/conformance oracle + linker presence

say "-- cross targets (full tier) --"
need qemu-i386    cross qemu-user
need qemu-aarch64 cross qemu-user
need qemu-arm     cross qemu-user
need qemu-riscv32 cross qemu-user

say "-- optional --"
need xvfb-run nice xvfb "GTK smoke tests go RED without it"
need gdb      nice gdb  "test-debug-g needs it"
need readelf  nice binutils "sqlite libc-free check needs it"

say "-- push access (watcher must push tstate reports) --"
url="$(git remote get-url origin 2>/dev/null || echo none)"
say "  origin: $url"
case "$url" in
  git@github.com:*|ssh://*)
    if git ls-remote --heads origin >/dev/null 2>&1; then
      say "  ok       ssh fetch works (push assumed if the key has write access)"
    else
      say "  MISSING  ssh access to origin failed — install a deploy key with write access"
      missing=1
    fi ;;
  https://*)
    say "  WARNING  https remote — pushes will prompt for credentials; prefer ssh:"
    say "           git -C $ROOT remote set-url origin git@github.com:yoctobyte/pxx.git" ;;
  none)
    say "  MISSING  no origin remote"; missing=1 ;;
esac

say "-- stable seed --"
if [ -x stable_linux_amd64/default/pinned ]; then
  say "  ok       stable_linux_amd64/default/pinned (compiler self-seeds, no FPC needed)"
else
  say "  MISSING  stable_linux_amd64/default/pinned — repo checkout incomplete?"
  missing=1
fi

say "-- corpus trees (gitignored; jobs self-skip when absent) --"
# Derived from twatch.CORPUS_EXPECTED, never copied: the hardcoded list this
# replaced had drifted from it (missing fpc-testsuite), so the setup script
# reported a complete clone while a corpus job self-skipped. Fail loudly if the
# constant cannot be read -- a fallback list would just recreate the drift.
corpus_trees=$(python3 -c "
import importlib.util
s = importlib.util.spec_from_file_location('tw', 'tools/twatch.py')
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(' '.join(m.CORPUS_EXPECTED))") || {
  say "  ERROR    cannot read CORPUS_EXPECTED from tools/twatch.py"; exit 1; }
for t in $corpus_trees; do
  if have_tree "library_candidates/$t"; then
    say "  ok       library_candidates/$t"
  else
    say "  absent   library_candidates/$t (corpus jobs SKIP; fetch with --fetch-corpus)"
    corpus_ok=0
  fi
done
# EXTERNAL corpus trees live under a DIFFERENT root with a DIFFERENT fetcher,
# and were invisible here until 2026-08-29. `external/synapse` was absent on a
# box this script had just called READY, so `lib-test` self-skipped one job and
# reported green -- the same tree, and the same silence, that track-t.md's
# "which numbers have never changed?" section was written about after a
# two-month hole. Derived from testmgr.CORPUS_FETCHERS for the same reason the
# list above is derived: a second copy is a second thing to drift.
say "-- external corpus trees (different root, different fetcher) --"
external_trees=$(python3 -c "
import importlib.util
s = importlib.util.spec_from_file_location('tm', 'tools/testmgr.py')
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(' '.join('%s/%s' % k for k in m.CORPUS_FETCHERS))") || {
  say "  ERROR    cannot read CORPUS_FETCHERS from tools/testmgr.py"; exit 1; }
for t in $external_trees; do
  if have_tree "$t"; then
    say "  ok       $t"
  else
    say "  absent   $t (corpus jobs SKIP; fetch with --fetch-corpus)"
    corpus_ok=0
  fi
done

# CROSS-TARGET GUEST RUNTIMES. Unlike every check above, absence here does NOT
# self-skip: tools/run_target.sh needs QEMU_LD_PREFIX to point at a guest ld.so,
# and without one the binary never executes and testmgr records a FAIL. Measured
# on seven 2026-08-29, first full tier on a box built strictly to the documented
# recipe: TEN jobs red with `qemu-i386: Could not open '/lib/ld-linux.so.2'`,
# auto-filed as an 18-job cascade naming twelve innocent commits.
#
# That is why this section exists and why it gates the verdict. A missing corpus
# announces itself as a SKIP; a missing sysroot is indistinguishable from a
# regression in the tree.
say "-- cross-target guest runtimes (full tier; absent = RED, not SKIP) --"
sysroot="${PXX_CROSS_SYSROOT:-$HOME/.cache/pxx-cross}"
# Derived from the installer's own provision lines, never copied.
for a in $(sed -n 's/^provision  *\([a-z0-9]*\) .*/\1/p' tools/install_cross_sysroot.sh); do
  if have_tree "$sysroot/$a/lib"; then
    say "  ok       $sysroot/$a"
  else
    say "  absent   $sysroot/$a (extern-C cross tests FAIL; fetch with --fetch-corpus)"
    sysroot_ok=0
  fi
done
# The i386 loader is a SYSTEM package, so it is a hint and never auto-installed:
# this script does not sudo, and a setup tool that installs system packages
# behind your back is a worse trade than a red it can name.
if [ -e /lib/ld-linux.so.2 ] || [ -e /lib32/ld-linux.so.2 ]; then
  say "  ok       /lib/ld-linux.so.2 (i386 guest loader)"
else
  say "  absent   /lib/ld-linux.so.2 — i386 extern-C tests FAIL. apt install libc6-i386"
  sysroot_ok=0
fi

# The uforth tree is named by the job's own SKIP line, which carries the exact
# clone command; 13 jobs self-skip without it.
say "-- uforth corpus (13 jobs self-skip when absent) --"
if have_tree "${UFORTH_DIR:-$HOME/projects/uforth}"; then
  say "  ok       ${UFORTH_DIR:-$HOME/projects/uforth}"
else
  say "  absent   ${UFORTH_DIR:-$HOME/projects/uforth} — git clone git@github.com:yoctobyte/uforth ${UFORTH_DIR:-$HOME/projects/uforth}"
  corpus_ok=0
fi

if [ "${1:-}" = "--fetch-corpus" ]; then
  say "-- fetching corpus trees --"
  tools/install_lib_candidates.sh all && corpus_ok=1
  # Both of these existed all along and neither was reachable from the deploy
  # recipe. install_externals.sh has fetched synapse since 2026-06-07;
  # install_cross_sysroot.sh needs no sudo (it apt-DOWNLOADS and extracts into
  # ~/.cache). A fetcher nothing calls is the same as no fetcher.
  say "-- fetching external corpus trees --"
  tools/install_externals.sh && corpus_ok=1
  say "-- provisioning cross-target guest runtimes --"
  tools/install_cross_sysroot.sh && sysroot_ok=1
fi

say "== verdict =="
if [ "$missing" = 1 ]; then
  say "NOT READY — fix the MISSING lines above."
  exit 1
fi
if [ "$cross_ok" = 1 ] && [ "$sysroot_ok" != 1 ]; then
  # NOT "READY (with caveats)". The whole finding behind this section is that a
  # box able to report and unable to measure reads as ready from outside, so the
  # verdict has to change, not gain a parenthesis.
  say "READY for --tier full EXCEPT the cross extern-C tests, which will FAIL"
  say "  — not skip. Run --fetch-corpus (and apt install libc6-i386 if named"
  say "  above) before trusting a cross-target red from this box."
elif [ "$cross_ok" = 1 ]; then
  say "READY for --tier full$( [ $corpus_ok = 1 ] || echo ' (corpus jobs will SKIP)' )"
else
  say "READY for --tier limited only (install qemu-user for full)"
fi
say "start:  nohup $ROOT/tools/twatch.py --clone $ROOT >> $ROOT.log 2>&1 &"
say "status: $ROOT/tools/twatch.py --status"
exit 0
