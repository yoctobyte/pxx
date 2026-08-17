#!/usr/bin/env bash
# Refuse to let third-party source enter the repo.
#
# The invariant (owner, 2026-08-17): fetched trees are NEVER committed. They are
# gitignored, fetched on demand, pinned, with a PROVENANCE.md. library_candidates/
# alone is ~146M; a single `git add -f` makes that a permanent object in the
# project's history, and history is the one thing we cannot quietly clean up.
#
# There are already two guards, and both have a hole this one closes:
#
#   1. .gitignore        — defeated by `git add -f`, and silent about a vendor
#                          root nobody remembered to list.
#   2. the fetchers' own `check-ignore` refusal (install_lib_candidates.sh,
#                          install_externals.sh) — only protects the roots those
#                          two scripts happen to know about.
#
# Neither notices a THIRD fetcher added later that forgets the guard. That is the
# repo's recurring failure shape — "the property holds and nothing enforces it",
# a missing edge rather than a broken thing, invisible to every gate because a
# gate can only fail on what it was told to look at.
#
# So this check does NOT hardcode the roots. It DERIVES them from the fetchers,
# and fails loudly on a fetcher whose destination it cannot determine. Adding a
# new fetcher therefore forces a decision instead of silently widening the hole.
#
# Cheap by construction (git ls-files over a handful of prefixes, well under a
# second), which is what lets it live in the per-fix gate rather than a nightly.
#
# Exit 0 clean, 1 on a violation. No writes, no network.

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "check-no-vendor-tracked: not a git repository" >&2
  exit 1
}
cd "$ROOT"

RC=0
fail() { echo "check-no-vendor-tracked: $*" >&2; RC=1; }

# --- derive the vendor roots from the fetchers themselves --------------------
# Every tools/install_*.sh that clones is expected to define its destination as
# DEST="$ROOT/<dir>". We read that rather than keeping a parallel list, because a
# parallel list is a second mechanism for one concept and would drift.
roots=""
shopt -s nullglob
for f in tools/install_*.sh; do
  # EVERY install_*.sh is in scope until it declares otherwise. There is
  # deliberately no "does this script actually fetch?" heuristic here, and the
  # first draft of this check is why: it tested for `git clone|curl|wget`, and
  # install_externals.sh fetches with `git -C "$tmp" init` + `fetch`, so the one
  # script this was written for was silently skipped as a non-fetcher. The check
  # then reported OK while protecting exactly one of the two roots.
  #
  # That is this repo's signature failure — a TRUE fact ("no `git clone` in this
  # file") about the WRONG subject ("does third-party source arrive through it").
  # A heuristic here can only ever be a guess about an open-ended question, and a
  # guess that fails SILENTLY. A naming convention cannot be missed: the cost of a
  # false positive is one declaration line, the cost of a false negative is 146M
  # in the project's history.

  # A script may declare itself out of scope, but it must SAY SO in its own
  # text — an explicit line a human wrote and a reviewer can weigh. Deriving the
  # exemption instead (e.g. "the path looks absolute") would recreate the guess
  # this check exists to remove. install_esp32_target.sh is the real case: it
  # clones esp-idf to $HOME, not into the tree.
  if grep -q 'no-vendor-tracked: out-of-scope' "$f"; then
    continue
  fi

  # Accept DEST= or any *_DIR= naming a path under $ROOT. Two spellings are
  # already in use (DEST in install_lib_candidates.sh, EXTERNAL_DIR in
  # install_externals.sh) and normalising them would mean editing a file another
  # lane is live in, to no benefit — the check reads them, it does not need them
  # identical. ROOT itself is excluded: it is the repo, not a destination.
  d=$(sed -nE 's@^[[:space:]]*(DEST|[A-Z0-9_]*_DIR)="?\$ROOT/([A-Za-z0-9_.-]+)"?[[:space:]]*$@\2@p' "$f" | head -1)
  if [ -z "$d" ]; then
    fail "$f is an install script whose destination could not be determined.
    Expected a line of the form:  DEST=\"\$ROOT/<dir>\"  (or <NAME>_DIR=\"\$ROOT/<dir>\")
    — or, if it cannot bring third-party source into the tree, the line
      'no-vendor-tracked: out-of-scope' in a comment, with the reason.
    This check derives the protected roots from the fetchers on purpose, so an
    unparseable one is a REAL failure, not a false positive: it means a path
    third-party source can arrive through that nothing is watching. Either give
    the script that DEST form, or state here why it cannot bring in vendor code."
    continue
  fi
  roots="$roots $d"
done
shopt -u nullglob

[ -n "${roots// /}" ] || fail "no fetcher destinations found — this check has
    silently stopped protecting anything. Verify tools/install_*.sh still exist
    and still declare DEST."

# --- the two properties, per root --------------------------------------------
for d in $roots; do
  # (a) it must be ignored. Checked even when the directory is absent: a fresh
  #     clone has no external/ yet, and that is exactly when a later fetch would
  #     land unprotected.
  if ! git check-ignore -q "$d/"; then
    fail "'$d/' is NOT gitignored. A fetch into it would be stageable.
    Fix: add '$d/' to .gitignore."
  fi

  # (b) nothing under it may be tracked. This is the property that survives
  #     `git add -f`, which is the whole reason .gitignore alone is not enough.
  n=$(git ls-files -- "$d/" | wc -l)
  if [ "$n" -ne 0 ]; then
    fail "$n tracked path(s) under '$d/' — third-party source is IN THE REPO.
    First few:
$(git ls-files -- "$d/" | head -5 | sed 's/^/      /')
    Fix, before this is pushed:  git rm -r --cached $d/
    If it is already pushed, say so — removing it from history is a different and
    much larger operation than removing it from the tree, and the owner decides."
  fi
done

# --- the path that has actually leaked once ----------------------------------
# esp-idf is cloned outside the tree, but it BUILDS into examples/esp32/*/build/,
# and a 9.1MB libwpa_supplicant.a from there is in this repo's history. It is
# gitignored today; it evidently was not always. Checked explicitly because the
# fetcher-derived loop above cannot see it — the tree that arrives is not the
# tree that gets written.
bt=$(git ls-files -- 'examples/esp32/*/build/' | wc -l)
if [ "$bt" -ne 0 ]; then
  fail "$bt tracked path(s) under examples/esp32/*/build/ — IDF build output is
    in the repo. This has happened before (a 9.1MB libwpa_supplicant.a is still
    in history). Fix:  git rm -r --cached examples/esp32/*/build/"
fi

if [ "$RC" -eq 0 ]; then
  echo "no vendor tracked: ok (${roots# } — ignored, 0 tracked)"
fi
exit "$RC"
