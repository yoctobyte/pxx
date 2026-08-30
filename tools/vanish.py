#!/usr/bin/env python3
"""Vanished-identifier scan — the detector for a SILENTLY CLOBBERED change.

WHAT THIS CATCHES, AND WHY NOTHING ELSE DOES
--------------------------------------------
A lane parks a held change as a whole-file COPY of a shared file and later
restores it over a tree that moved underneath. Git sees a well-formed commit,
merges it without a conflict, and another lane's work is gone. This actually
happened on 2026-08-30 (frankS parking `defs.inc` / `cpreproc.inc` across a
pin; restoring would have deleted frankA's `CUnitOfPascalProgram` block and
124 changed lines of `cpreproc.inc`) and is written up in
`devdocs/dev/coordination-overhead-2026-08-30.md`.

No test tier can see this, and that is structural rather than a gap in tier
composition: every job in `tools/testmgr.py` builds something and runs it, so
a deleted symbol is observable ONLY through a live caller. Clobber something
self-contained — a helper landed an hour ago, a function not yet called, a
test — and it compiles clean, reaches a valid self-host fixedpoint, passes
`quick`, and lands. The one case we observed surfaced as `undefined variable`
purely because the reverted code happened to have a caller. That is luck, and
luck is not a control. Adding tiers does not help; more tiers means more
callers, not a different question.

So the detector cannot live in the matrix. It lives in the DIFF, where the
deletion is visible whether or not anything called it.

DIFF IDENTIFIERS, NOT DECLARATION SHAPES.  <-- do not "clean this up"
--------------------------------------------------------------------
The tempting implementation looks for removed `function` / `procedure`
declarations. It is about ten times quieter (4 names/day against 73), it reads
like the obviously-correct thing, and IT MISSES THE ONLY CASE WE HAVE EVER
OBSERVED: `CUnitOfPascalProgram` is a global `var` in `compiler/defs.inc`, not
a routine. A clobber deletes whatever the other lane happened to add — a var, a
const, a type, a field, an enum member, a case arm — and a detector that only
understands routines is blind to most of that surface while looking tidier than
the one that works.

The noise is the cost of the coverage and is meant to stay visible. If a future
pass "improves" this by restricting to declarations, or by stoplisting the
English words that leak in from comment prose, it will get quieter and stop
doing its job. Rank the output; never filter it. That is what step 4 below is
for, and it is why there is no --only-interesting flag to add.

`tools/devtest_vanish.py` is the positive control, and it asserts BOTH halves:
that a synthesised whole-file-copy clobber is caught, and that the tidier
declaration-shaped detector misses that same clobber. The second assertion is
the one that will fail when somebody makes this quieter.

HOW IT WORKS
------------
1. One `git log -p --unified=0` over the range (~1.2s for a day of compiler
   diffs). No per-commit git invocations in the hot path.
2. Per commit: identifiers on removed lines MINUS identifiers on added lines.
3. Tree-presence filter — keep only names that no longer occur ANYWHERE in the
   scanned paths at that commit. This is what removes the false positives that
   matter: a routine MOVED between files still occurs, so a refactor that
   relocates code is silent here, while a deletion is not.
4. Annotate each survivor with when it was introduced and by which lane. A
   name that was added hours ago by a DIFFERENT lane and is now gone is the
   clobber shape; a name the same lane added and removed is ordinary churn.

Steps 1-3 are the detector. Step 4 is the ranking, and is the only part that
costs real time (one pickaxe per surviving name).

Usage:
  tools/vanish.py                      # last 24h on HEAD
  tools/vanish.py --since '3 days ago'
  tools/vanish.py --range A..B
  tools/vanish.py --publish            # also write tstate/vanished.md
  tools/vanish.py --no-annotate        # skip step 4 (fast, unranked)

Exit status is 0 whether or not anything is flagged: this REPORTS, it does not
gate. A flagged commit is nearly always legitimate (a deliberate deletion, a
rename, a fold) — the list is short enough to read, which is the entire design
goal. Do not wire it into a gate; wire it into a habit.
"""
import argparse
import collections
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
TSTATE_REL = "devdocs/progress/tstate"

# Rebound by --repo so the devtest can drive this against a scratch repo that
# contains a synthesised clobber. A detector with no positive control is the
# same class of claim as a green from one shape, so being runnable somewhere
# other than this checkout is a requirement, not a convenience.
_repo = REPO

# The shared files a clobber would land in. Deliberately not the whole tree:
# `docs/**` and ticket markdown churn constantly and carry no callers, so they
# would swamp the signal without ever hosting the failure this exists for.
DEFAULT_PATHS = ["compiler/", "lib/", "tools/"]

# 4+ chars: shorter names are loop counters and single-letter locals, which
# vanish constantly and mean nothing. Not a stoplist — a length floor, applied
# to every identifier equally rather than to a hand-picked set of words.
IDENT = re.compile(r"\b[A-Za-z_]\w{3,}\b")

# `fix(A):`, `feat(N):`, `refactor(C+A):`, `docs(T):` -> the lane letters.
LANE = re.compile(r"^\w+\(([^)]*)\)")

# git grep alternation has a command-line length limit; chunk well under it.
GREP_CHUNK = 150


def git(*args, cwd=None, check=False):
    cwd = cwd or _repo
    r = subprocess.run(["git"] + list(args), cwd=cwd,
                       capture_output=True, text=True, errors="replace")
    if check and r.returncode != 0:
        sys.exit("git %s failed: %s" % (" ".join(args), r.stderr.strip()))
    return r.stdout


def lane_of(subject):
    m = LANE.match(subject or "")
    if not m:
        return ""
    return "+".join(sorted(p.strip().upper() for p in m.group(1).split("+")
                           if p.strip()))


def scan_diffs(rev_args, paths):
    """Step 1+2: {sha: (subject, {names only on removed lines})}, one git call."""
    out = git("log", "--format=@@C %H %s", "-p", "--unified=0",
              "--no-color", *rev_args, "--", *paths)
    removed = collections.defaultdict(set)
    added = collections.defaultdict(set)
    subject = {}
    cur = None
    for line in out.splitlines():
        if line.startswith("@@C "):
            rest = line[4:]
            sha, _, subj = rest.partition(" ")
            cur = sha
            subject[cur] = subj
            continue
        if cur is None or not line:
            continue
        # Skip diff furniture. `---`/`+++` are headers, not content; a hunk
        # header can carry a function-context tail that is not a change.
        if line.startswith(("+++", "---", "@@", "diff ", "index ",
                            "similarity ", "rename ", "new file", "deleted file",
                            "old mode", "new mode", "Binary files")):
            continue
        if line[0] == "-":
            removed[cur] |= set(IDENT.findall(line))
        elif line[0] == "+":
            added[cur] |= set(IDENT.findall(line))
    cand = {}
    for sha, names in removed.items():
        only = names - added.get(sha, set())
        if only:
            cand[sha] = (subject.get(sha, ""), only)
    return cand


def still_present(sha, names, paths):
    """Step 3: which of `names` still occur anywhere in `paths` at `sha`."""
    found = set()
    names = sorted(names)
    for i in range(0, len(names), GREP_CHUNK):
        chunk = names[i:i + GREP_CHUNK]
        out = git("grep", "-h", "-o", "-w", "-E",
                  "(" + "|".join(chunk) + ")", sha, "--", *paths)
        found |= set(out.split())
    return found


def introduced(name, sha, paths, window):
    """Step 4: the newest commit at or before `sha`^ that changed this name's
    count. For a freshly-added name that is where it came from, which is the
    signal we want; for an ancient name the pickaxe would walk a long way, so
    the window bounds it and 'older' is itself informative."""
    args = ["log", "-S" + name, "-n", "1", "--format=%H|%cI|%s"]
    if window:
        args += ["--since", window]
    args += [sha + "^", "--"] + paths
    out = git(*args).strip()
    if not out:
        return None
    h, _, rest = out.partition("|")
    date, _, subj = rest.partition("|")
    return h, date, subj


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--since", default="24 hours ago")
    ap.add_argument("--range", dest="rng", default=None,
                    help="a git range (A..B); overrides --since")
    ap.add_argument("--paths", nargs="*", default=DEFAULT_PATHS)
    ap.add_argument("--publish", action="store_true",
                    help="also write %s/vanished.md" % TSTATE_REL)
    ap.add_argument("--no-annotate", action="store_true",
                    help="skip the introduced-by lookup (fast, unranked)")
    ap.add_argument("--annotate-window", default="14 days ago",
                    help="how far back the introduced-by pickaxe walks")
    ap.add_argument("--repo", default=REPO,
                    help="repository to scan (the devtest points this at a "
                         "scratch repo carrying a synthesised clobber)")
    a = ap.parse_args()
    global _repo
    _repo = a.repo

    rev_args = [a.rng] if a.rng else ["--since", a.since, "HEAD"]
    scope = "range %s" % a.rng if a.rng else "since %s" % a.since

    cand = scan_diffs(rev_args, a.paths)
    rows = []
    for sha, (subj, names) in cand.items():
        gone = names - still_present(sha, names, a.paths)
        if not gone:
            continue
        rows.append({"sha": sha, "subject": subj, "lane": lane_of(subj),
                     "gone": sorted(gone)})

    # Step 4 — annotate, and rank by the clobber shape: a name introduced by a
    # DIFFERENT lane, recently, is what a silent revert looks like. Nothing is
    # dropped; this only decides reading order.
    if not a.no_annotate:
        for r in rows:
            r["src"] = {}
            for n in r["gone"]:
                got = introduced(n, r["sha"], a.paths, a.annotate_window)
                if got:
                    h, date, subj = got
                    r["src"][n] = {"sha": h, "date": date,
                                   "lane": lane_of(subj), "subject": subj}
        for r in rows:
            r["cross"] = sorted(n for n, s in r["src"].items()
                                if s["lane"] and r["lane"]
                                and s["lane"] != r["lane"])
        rows.sort(key=lambda r: (-len(r["cross"]), -len(r["gone"])))
    else:
        for r in rows:
            r["src"], r["cross"] = {}, []
        rows.sort(key=lambda r: -len(r["gone"]))

    ncross = sum(len(r["cross"]) for r in rows)
    lines = []
    lines.append("# Vanished identifiers — %s" % scope)
    lines.append("")
    lines.append("Identifiers deleted by a commit that occur nowhere in `%s` "
                 "afterwards. Nearly all are deliberate; the list exists so a "
                 "SILENT clobber — another lane's work removed with no conflict "
                 "and no failing test — has somewhere to show up. See the "
                 "header of `tools/vanish.py`."
                 % ", ".join(a.paths))
    lines.append("")
    lines.append("- commits scanned with any removal: **%d**" % len(cand))
    lines.append("- commits with a vanished identifier: **%d**" % len(rows))
    lines.append("- vanished identifiers: **%d**"
                 % sum(len(r["gone"]) for r in rows))
    lines.append("- of those, introduced by a DIFFERENT lane (the clobber "
                 "shape): **%d**" % ncross)
    lines.append("")
    for r in rows:
        mark = " **[cross-lane]**" if r["cross"] else ""
        lines.append("## `%s` %s%s" % (r["sha"][:9], r["subject"], mark))
        for n in r["gone"]:
            s = r["src"].get(n)
            if s:
                flag = " <-- added by %s" % s["lane"] if n in r["cross"] else ""
                lines.append("- `%s` — added `%s` %s by %s%s"
                             % (n, s["sha"][:9], s["date"][:16],
                                s["lane"] or "?", flag))
            else:
                lines.append("- `%s`" % n)
        lines.append("")

    text = "\n".join(lines)
    print(text)
    if a.publish:
        p = os.path.join(_repo, TSTATE_REL, "vanished.md")
        with open(p, "w") as f:
            f.write(text + "\n")
        print("written: %s" % p, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
