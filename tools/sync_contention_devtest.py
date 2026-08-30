#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: sync.sh stops widening the window it is racing in, and its backoff
is actually random.

Two independent findings from chore-t-push-contention-is-a-fleet-property-not-
an-anomaly, both measured on plexus 2026-08-30:

1. `rebase_onto_origin` regenerated the boards unconditionally, on every retry,
   INSIDE the fetch->push window -- 18-21s of it, ~87% spent writing BOARD.html,
   which is gitignored and never staged. sync.sh was making its own next race
   more likely on every attempt to escape the last one.

2. `push_with_retry` slept `"$tries"`. Its own comment said the pause exists so
   that racing writers stop retrying in lockstep -- and an identical delay in
   every process is the one thing that cannot do that. Two writers colliding at
   t=0 both wake at t=1 and stay in phase for the whole budget.

The second is the shape worth naming: **a mechanism whose comment states the
property its implementation lacks.** It reads as done. The only way to catch it
is to test the property, not the presence of the pause -- so guard 1 below
asserts the samples DIFFER, which is exactly what the old line failed and what
"there is a sleep here" would have passed.

The fingerprint guards are the other half: skipping is safe only if the
fingerprint moves when a ticket moves, and it is USEFUL only if it stays put
when the watcher publishes tstate. Both directions are tested; either alone is
a green that means nothing.

Run: python3 tools/sync_contention_devtest.py
"""

import os
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
SYNC = (ROOT / "tools" / "sync.sh").read_text(encoding="utf-8")
fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-58s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def sh_func(name):
    """Lift one shell function out of sync.sh, verbatim.

    Verbatim on purpose: a copy of the logic in this file would pass forever
    after sync.sh changed underneath it.
    """
    m = re.search(r"^%s\(\) \{\n.*?^\}\n" % re.escape(name), SYNC, re.S | re.M)
    if not m:
        raise AssertionError("sync.sh has no %s()" % name)
    return m.group(0)


def sh(script, cwd=None):
    r = subprocess.run(["sh", "-c", script], cwd=cwd, capture_output=True,
                       text=True, timeout=120)
    return r.returncode, r.stdout, r.stderr


def samples(t, n=200):
    rc, out, err = sh(sh_func("jittered_backoff") +
                      "\ni=0\nwhile [ $i -lt %d ]; do jittered_backoff %d; "
                      "i=$((i+1)); done\n" % (n, t))
    assert rc == 0, err
    return [float(x) for x in out.split()]


def git(cwd, *args):
    subprocess.run(("git",) + args, cwd=cwd, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def fingerprint(repo):
    rc, out, err = sh(sh_func("ticket_fingerprint") + "\nticket_fingerprint\n",
                      cwd=repo)
    assert rc == 0, err
    return out.strip()


def scratch_repo(base):
    repo = base / "r"
    (repo / "devdocs/progress/backlog").mkdir(parents=True)
    (repo / "devdocs/progress/tstate").mkdir(parents=True)
    git(base, "init", "-q", "--initial-branch=master", str(repo))
    git(repo, "config", "user.email", "d@d")
    git(repo, "config", "user.name", "d")
    (repo / "devdocs/progress/backlog/bug-x.md").write_text("one\n")
    (repo / "devdocs/progress/tstate/plexus.json").write_text("{}\n")
    (repo / "devdocs/progress/BOARD.md").write_text("board\n")
    (repo / "devdocs/progress/BOARD-brief.md").write_text("brief\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "init")
    return repo


def commit(repo, path, text):
    p = repo / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "x")


def main():
    print("1. the backoff is RANDOM -- the guard `sleep \"$tries\"` fails")
    s1 = samples(1)
    check(len(set(s1)) > 100, "200 draws at tries=1 are not one value",
          "%d distinct" % len(set(s1)))
    check(all(0.5 <= v < 1.5 for v in s1), "all within [tries/2, 3*tries/2)",
          "min %.3f max %.3f" % (min(s1), max(s1)))
    m1 = sum(s1) / len(s1)
    check(0.90 <= m1 <= 1.10, "and the MEAN is still `tries`, so no patience lost",
          "mean %.3f" % m1)

    print("2. it still grows, and the range grows with it")
    s12 = samples(12)
    check(all(6.0 <= v < 18.0 for v in s12), "tries=12 stays in [6, 18)",
          "min %.3f max %.3f" % (min(s12), max(s12)))
    m12 = sum(s12) / len(s12)
    check(11.0 <= m12 <= 13.0, "mean tracks tries", "mean %.3f" % m12)
    check(max(s12) - min(s12) > max(s1) - min(s1),
          "spread widens with the attempt, so late retries decorrelate more")

    print("3. and `sleep` can actually parse what it emits")
    check(all(re.fullmatch(r"\d+\.\d{3}", x) for x in
              sh(sh_func("jittered_backoff") + "\njittered_backoff 3\n")[1].split()),
          "fixed 3-decimal form, never bare or exponential")
    rc, _, _ = sh(sh_func("jittered_backoff") +
                  "\nsleep \"$(jittered_backoff 1)\"\n")
    check(rc == 0, "and sleep accepts it")

    print("4. the ticket fingerprint IGNORES what the board ignores")
    import tempfile
    with tempfile.TemporaryDirectory(
            dir=os.environ.get("TESTMGR_TMP") or os.environ.get("TMPDIR") or "/tmp"
    ) as td:
        repo = scratch_repo(pathlib.Path(td))
        base = fingerprint(repo)
        check(fingerprint(repo) == base, "it is stable across calls")
        commit(repo, "devdocs/progress/tstate/plexus.json", '{"n":1}\n')
        check(fingerprint(repo) == base,
              "a tstate publish does not move it -- the whole point")
        commit(repo, "devdocs/progress/tstate/seven.json", "{}\n")
        check(fingerprint(repo) == base, "nor does a NEW tstate file")
        commit(repo, "devdocs/progress/BOARD.md", "regenerated\n")
        check(fingerprint(repo) == base, "nor the generated BOARD.md")
        commit(repo, "devdocs/progress/BOARD-brief.md", "regenerated\n")
        check(fingerprint(repo) == base, "nor BOARD-brief.md")

        print("5. ...and MOVES for anything that changes a board")
        commit(repo, "devdocs/progress/backlog/bug-x.md", "two\n")
        f_edit = fingerprint(repo)
        check(f_edit != base, "editing a ticket moves it")
        commit(repo, "devdocs/progress/urgent/bug-y.md", "new\n")
        f_new = fingerprint(repo)
        check(f_new != f_edit, "filing into a status dir that did not exist moves it")
        commit(repo, "devdocs/progress/float/f-1.md", "parked\n")
        check(fingerprint(repo) != f_new,
              "including a status the ranker never scans, which the board still shows")
        commit(repo, "devdocs/progress/backlog/BOARD-naming-ticket.md", "t\n")
        check(fingerprint(repo) != base,
              "a TICKET whose name starts with BOARD is not mistaken for a board")
        git(repo, "rm", "-q", "devdocs/progress/backlog/bug-x.md")
        git(repo, "commit", "-qm", "rm")
        check(fingerprint(repo) != f_new, "and a deletion moves it too")

    print("6. it is cheap enough to run inside the race window")
    t0 = time.time()
    fingerprint(ROOT)
    dt = time.time() - t0
    check(dt < 2.0, "under 2s on the real tree (a bound, not a benchmark)",
          "%.3fs" % dt)

    print("7. sync.sh asks for the markdown only, at every regeneration site")
    calls = re.findall(r"progress\.sh board-md[^\n]*", SYNC)
    check(len(calls) >= 2, "both regeneration sites are still there",
          "%d call(s)" % len(calls))
    check(all("--no-html" in c for c in calls),
          "and neither pays for the gitignored BOARD.html")
    check("TICKETS_FINGERPRINT=$fp" in SYNC,
          "the fingerprint is recorded AFTER the regeneration, not before")

    print("8. progress.py honours --no-html, and still writes html by default")
    sys.path.insert(0, str(ROOT / "tools"))
    import progress                                                # noqa: E402
    check("tstate" not in progress.STATUSES,
          "tstate is not a ticket status -- what the exclusion rests on",
          ",".join(progress.STATUSES[:3]) + ",...")

    seen = []

    class FakeBoard:
        def write_board_md(self):
            seen.append("md")

        def write_board_html(self):
            seen.append("html")

    real, progress.Board = progress.Board, FakeBoard
    try:
        seen.clear()
        progress.main(["board-md", "--no-html"])
        check(seen == ["md"], "--no-html writes the markdown and nothing else",
              str(seen))
        seen.clear()
        progress.main(["board-md"])
        check(seen == ["md", "html"], "the bare command is unchanged for humans",
              str(seen))
    finally:
        progress.Board = real

    print("\n  %d guard(s), %d FAIL" % (24, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
