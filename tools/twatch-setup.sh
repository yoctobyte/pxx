#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Track T watcher box setup check (feature-track-t-watcher).
#
# Verifies a box can run tools/twatch.py at full tier and prints exactly
# what's missing (with apt hints). Read-only by default; --fetch-corpus
# additionally pulls the gitignored third-party trees.
#
# Deploy one-liner on a fresh box:
#   git clone git@github.com:yoctobyte/pxx.git ~/trackt \
#     && ~/trackt/tools/twatch-setup.sh --fetch-corpus \
#     && nohup ~/trackt/tools/twatch.py --clone ~/trackt >> ~/trackt.log 2>&1 &
#
# Exit 0 = full tier capable; 1 = something missing (message says what, and
# which reduced tier still works).
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
missing=0; cross_ok=1; corpus_ok=1

say()  { printf '%s\n' "$*"; }
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
for t in lua sqlite zlib c-testsuite tcc cjson; do
  if [ -d "library_candidates/$t" ]; then
    say "  ok       library_candidates/$t"
  else
    say "  absent   library_candidates/$t (corpus jobs SKIP; fetch with --fetch-corpus)"
    corpus_ok=0
  fi
done
if [ "${1:-}" = "--fetch-corpus" ]; then
  say "-- fetching corpus trees --"
  tools/install_lib_candidates.sh all && corpus_ok=1
fi

say "== verdict =="
if [ "$missing" = 1 ]; then
  say "NOT READY — fix the MISSING lines above."
  exit 1
fi
if [ "$cross_ok" = 1 ]; then
  say "READY for --tier full$( [ $corpus_ok = 1 ] || echo ' (corpus jobs will SKIP)' )"
else
  say "READY for --tier limited only (install qemu-user for full)"
fi
say "start:  nohup $ROOT/tools/twatch.py --clone $ROOT >> \$HOME/trackt.log 2>&1 &"
say "status: $ROOT/tools/twatch.py --status"
exit 0
