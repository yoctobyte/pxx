#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Say which twatch.py a REMOTE watcher daemon is actually running.

    tools/twatch_live_code.py [--host seven] [--repo .]

WHY THIS EXISTS
---------------
`trackt status` answers this with its `code :` row, and that row is computed
from the daemon's watch file in the daemon's OWN clone -- `set_phase()` writes
it with `write_json_atomic(clone.path/WATCH_REL)` and nothing publishes it. So
the check works only on the box the daemon runs on. Track T runs on seven and
plexus deliberately does not run a watcher, so from anywhere else `trackt
status` prints `daemon : STOPPED` about the local clone and no `code :` row at
all: correct about the wrong machine, which is the failure mode CLAUDE.md
already records for `trackt health`.

The fingerprint IS published, though, on every full-schema archive row. Joining
it against git answers the question from any checkout with no ssh:

    running code_fp  ==  sha256(git show <commit>:tools/twatch.py)[:12]

Measured 2026-09-06: seven was running 7327e547732c = 17854b85b (2026-09-05
19:45), with FIVE landed twatch.py commits absent from the process publishing
verdicts. Three sessions re-derived some version of this check in one evening
and one of them (mine) first concluded the question was unanswerable without
ssh. It is answerable; it was just not a command.

WHAT IT DOES NOT DO
-------------------
It does not say whether the daemon is UP, whether a tier is in flight, or
whether a restart is safe. A fingerprint is a statement about code identity and
nothing else. `A RESTART DESTROYS A RUN IN FLIGHT` is a separate question with a
separate instrument (publish cadence in the archive), and this tool stays silent
about it rather than implying an answer.

AN UNRESOLVED FINGERPRINT IS REPORTED AS UNKNOWN, NEVER AS THE NEAREST MATCH.
A daemon can run code that was never pushed, or that has since been rebased out
of the history we can see. "I cannot identify this" and "this is current" must
not be the same output, because the whole point is to distinguish them.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch                                            # noqa: E402

WATCHED = "tools/twatch.py"


def sh(args, repo):
    r = subprocess.run(args, cwd=repo, text=True, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("%s failed: %s" % (" ".join(args), r.stderr.strip()[:300]))
    return r.stdout


def fp_at(repo, commit):
    """The fingerprint twatch.py would report if started at `commit`."""
    r = subprocess.run(["git", "show", "%s:%s" % (commit, WATCHED)],
                       cwd=repo, capture_output=True)
    if r.returncode != 0:
        return None
    return hashlib.sha256(r.stdout).hexdigest()[:12]


def archive_dir(repo, override):
    """Where to read runs-<host>.ndjson from, and a label saying which.

    THE WORKTREE IS A POINT-IN-TIME SNAPSHOT AND THIS TOOL IS MOST USEFUL IN THE
    ONE CHECKOUT WHERE THAT BITES. The watcher clone spends its life detached at
    whatever sha it is testing, so `devdocs/progress/tstate/runs-seven.ndjson`
    on disk there is that sha's archive -- and a stale archive yields a stale
    code_fp, which this tool would then resolve confidently to the wrong commit
    and report as CURRENT. That is the failure this whole tool exists to catch,
    reproduced one level up in the tool itself.

    So the default reads the tstate subtree out of the git REF via
    twatch.materialize_tstate(), the shared helper whose docstring records four
    bugs in one day from reading the worktree -- the fourth reproducing the
    second hours after it was fixed. Knowing the rule was not enough for them
    and it was not enough for me: the first version of this file read by path.

    Falls back to the worktree only when the ref carries no tstate (a fresh
    clone, a repo without the remote), deliberately and out loud, so a fallback
    is never mistaken for the normal path.
    """
    if override:
        return os.path.abspath(override), "explicit --archive"
    d = twatch.materialize_tstate(repo)
    if d:
        return d, "git ref %s" % twatch.origin_ref()
    return repo, "WORKTREE FALLBACK (the ref carries no tstate)"


def running_fp(archive, host):
    """The newest published code_fp for `host`, with the row's timestamp.

    Rows written before the stamp existed, and the thin requested-verify rows,
    carry no code_fp at all -- so we scan BACKWARDS for the newest row that has
    one rather than reading the last row and calling an absence a value.
    """
    path = os.path.join(archive, "devdocs/progress/tstate/runs-%s.ndjson" % host)
    if not os.path.exists(path):
        return None, None, "no archive at %s" % path
    rows = 0
    with open(path) as f:
        lines = f.readlines()
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        rows += 1
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("code_fp"):
            return d["code_fp"], d.get("date"), None
    return None, None, ("scanned %d row(s) for host %s and none carries a "
                        "code_fp -- either the daemon predates the stamp or "
                        "this host publishes only thin rows" % (rows, host))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="seven")
    ap.add_argument("--repo", default=".",
                    help="git checkout whose twatch.py history is searched")
    ap.add_argument("--archive", default=None,
                    help="read the archive from this directory instead of from "
                         "the git ref. For tests and for offline inspection; "
                         "the default goes through materialize_tstate() because "
                         "a worktree is a point-in-time snapshot.")
    ap.add_argument("--limit", type=int, default=60,
                    help="how far back through twatch.py's history to look")
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)

    # A git question asked of a non-git directory answers with git's own
    # discovery error, which reads like a tool failure rather than a usage one.
    if not os.path.isdir(os.path.join(repo, ".git")):
        print("twatch-live: --repo %s is not a git checkout, so twatch.py's "
              "history cannot be searched. Pass --repo <checkout> (and "
              "--archive if the published rows live elsewhere)." % repo)
        return 2

    archive, how = archive_dir(repo, a.archive)
    fp, when, err = running_fp(archive, a.host)
    if err:
        print("twatch-live: %s" % err)
        return 2
    print("twatch-live: host %s publishes code_fp %s (newest row %s, read from %s)"
          % (a.host, fp, when, how))

    hist = sh(["git", "log", "--format=%H %h %ci %s", "-%d" % a.limit,
               "--", WATCHED], repo).splitlines()
    match = None
    ahead = []
    for line in hist:
        full, short, rest = line.split(" ", 2)
        if fp_at(repo, full) == fp:
            match = (short, rest)
            break
        ahead.append((short, rest))

    if not match:
        print("twatch-live: UNKNOWN — that fingerprint matches no %s in the "
              "last %d commit(s) touching it. The daemon may be running code "
              "that was never pushed, or that has been rebased out. NOT "
              "reporting a nearest match." % (WATCHED, a.limit))
        return 3

    short, rest = match
    print("twatch-live: running %s (%s)" % (short, rest))
    if not ahead:
        print("twatch-live: CURRENT — no %s commit has landed since." % WATCHED)
        return 0
    print("twatch-live: STALE — %d %s commit(s) landed since and are NOT live:"
          % (len(ahead), WATCHED))
    for short, rest in reversed(ahead):
        print("    %s %s" % (short, rest))
    print("twatch-live: a restart makes them live. This tool does NOT say "
          "whether one is safe: check for a run in flight first.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
