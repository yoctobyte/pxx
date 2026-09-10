#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# Reap temp directories this repo's own tools left behind in $TESTTMP.
#
# THIS IS THE BACKSTOP, NOT THE FIX. The fix is the TMPDIR pin in testmgr.py's
# BASE_ENV_KEEP: every job a tier runs now gets TMPDIR=$RUN_TMP/tmp, so all ~150
# mkdtemp sites in tools/*_devtest.py land inside a directory that already has
# two teardowns (drop_run_tmp at exit, sweep_orphan_tmp's pid-keyed reclaim for
# the SIGKILL case). What is left over for this script is the population that
# pin cannot reach:
#
#   * dirs already standing from before the pin landed -- 1,048,561 inodes on
#     seven on 2026-09-07, 186 tstate-at.* on plexus on 2026-09-10;
#   * a devtest a human runs by hand, outside any tier;
#   * a helper killed by SIGKILL, where no atexit hook runs.
#
# Committed rather than typed, because CLAUDE.md says so in as many words:
# cleanup belongs in a script with a `trap ... EXIT`, reviewed once and run as a
# unit. An interactive rm with a glob or a variable in it is refused by
# .claude/hooks/no-variable-rm.sh, and routing around that guard is not the
# answer -- this script IS the answer, and the hook's own text says why it does
# not apply here: it sees `tools/foo.sh`, not what is inside it.
#
# Usage:  tools/reap_tmp.sh [-n] [-a HOURS]
#   -n        dry run: say what would go, remove nothing
#   -a HOURS  minimum age (default 6, matching /etc/tmpfiles.d/tmp.conf)
set -eu

AGE_H=6
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n) DRY=1 ;;
    -a) AGE_H="$2"; shift ;;
    -h|--help) sed -n '3,27p' "$0"; exit 0 ;;
    *) echo "reap_tmp: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TESTTMP="${TESTTMP-/tmp}"
TESTTMP_GIVEN="$TESTTMP"        # report what the caller SAID, not what %/ left
TESTTMP="${TESTTMP%/}"

# Refuse to operate on a root that would make the find below catastrophic. Not
# theatre: TESTTMP comes from the environment, and an empty or "/" value turns
# a maxdepth-1 name glob into a sweep of the filesystem root.
case "$TESTTMP" in
  ""|"/") echo "reap_tmp: refusing to reap TESTTMP='$TESTTMP_GIVEN'" >&2; exit 2 ;;
esac
[ -d "$TESTTMP" ] || { echo "reap_tmp: no such directory: $TESTTMP" >&2; exit 2; }

WORK="$(mktemp -d "$TESTTMP/reap-tmp-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

# The prefixes, READ OUT OF THE SOURCE rather than listed here.
#
# A hardcoded list is the house pattern (see RUNNER_BINARIES in twatch.py) and
# it is wrong for this one: there are 96 of them, a devtest is added most weeks,
# and a list that silently stopped covering the newest families would leave this
# script printing a confident "reaped 0" during the next outage. Deriving it
# means the script can only ever name a prefix some tool in this repo actually
# creates -- which is also the safety property that matters, since everything
# else under $TESTTMP belongs to somebody else.
#
# PREFIX-LESS mkdtemp() calls are deliberately NOT covered. ~60 sites pass no
# prefix and land on tempfile's default `tmp*`, which was 101,200 inodes in the
# outage census -- and `tmp*` in a shared /tmp is far too broad to delete by
# pattern. Those are covered by the TMPDIR pin when they run under a tier, and
# by nothing when they do not. Naming that gap rather than papering over it:
# the fix for them is a prefix at the call site, not a wider glob here.
python3 - "$REPO" > "$WORK/prefixes" <<'PYEOF'
import glob, os, re, sys
repo = sys.argv[1]
pats = (r'mkdtemp\(\s*prefix=["\']([^"\']+)["\']',
        r'TemporaryDirectory\(\s*\n?\s*prefix=["\']([^"\']+)["\']',
        r'mktemp -d "\$\{TMPDIR:-/tmp\}/([A-Za-z0-9_.-]+?)-?X')
seen = set()
for f in sorted(glob.glob(os.path.join(repo, 'tools', '*.py'))
                + glob.glob(os.path.join(repo, 'tools', '*.sh'))):
    try:
        t = open(f, encoding='utf-8', errors='replace').read()
    except OSError:
        continue
    for p in pats:
        for m in re.finditer(p, t):
            v = m.group(1)
            # A prefix short enough to collide with somebody else's files is
            # not worth the inodes it would reclaim.
            if len(v) >= 4 and v not in seen:
                seen.add(v)
print("\n".join(sorted(seen)))
PYEOF

nprefix=$(wc -l < "$WORK/prefixes")
echo "reap_tmp: $nprefix prefix(es) from $REPO/tools, root $TESTTMP, age >= ${AGE_H}h"

# Collect first, act second, so the count is reported even when nothing goes and
# so a dry run walks exactly the same code path as a real one.
: > "$WORK/victims"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  # -maxdepth 1: only the directory a helper created, never something nested
  # inside one that a live process may still be writing to.
  # -mmin: age in minutes, so -a accepts fractions of an hour for testing.
  find "$TESTTMP" -mindepth 1 -maxdepth 1 -type d -name "$p*" \
       -mmin "+$((AGE_H * 60))" -print >> "$WORK/victims" 2>/dev/null || true
done < "$WORK/prefixes"

sort -u "$WORK/victims" -o "$WORK/victims"

freed=0
ndir=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ -d "$d" ] || continue
  # Never a symlink: recursing through one would leave the target's contents
  # gone and the reason invisible.
  if [ -L "$d" ]; then continue; fi
  # A trailing pid means liveness is knowable, so ask instead of guessing --
  # the same rule sweep_orphan_tmp() uses, and the one that makes reaping safe
  # for a helper that is merely slow rather than dead.
  pid="${d##*[-.]}"
  case "$pid" in
    ''|*[!0-9]*) ;;
    *) if kill -0 "$pid" 2>/dev/null; then continue; fi ;;
  esac
  n=$(find "$d" 2>/dev/null | wc -l)
  freed=$((freed + n))
  ndir=$((ndir + 1))
  if [ "$DRY" -eq 1 ]; then
    echo "  would reap $d  ($n inodes)"
  else
    rm -rf -- "$d"
  fi
done < "$WORK/victims"

if [ "$DRY" -eq 1 ]; then
  echo "reap_tmp: would reap $ndir dir(s), $freed inode(s) — nothing removed"
else
  echo "reap_tmp: reaped $ndir dir(s), $freed inode(s)"
fi
python3 "$REPO/tools/fsheadroom.py" "$TESTTMP"
