#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: `check` says when the tree it just read is behind origin.

A PURE-READER SEAT HAS NO STALENESS SIGNAL AT ALL. Every staleness guard in this
repo keys on an artefact of DOING WORK -- an unpushed commit, a dirty file, the
`.fixedpoint` stamp, `converged` versus `verified`, a sha in a commit trailer.
A session that only reads the board and reports on it produces none of them, so
it drifts unboundedly while `git status` says `clean` the whole time. CLAUDE.md
says a clean tree is not evidence about a session -- but it says so about one
that has JUST LANDED, the opposite case, and nothing covers one that has NEVER
landed.

Measured 2026-09-06: the seat whose job is auditing every checkout's HEAD
against origin/master was 593 commits behind, found only because a peer noticed
one of its line citations was 281 off. The scan checked every peer and not
itself, because it was not one of the peers.

THE TWO NEGATIVE CONTROLS ARE THE POINT. A finding that fires on a tree merely
AHEAD of origin would fire on every session mid-work, and a finding everybody
scrolls past is worth less than no finding -- which is the failure this repo
names in as many words. So: behind fires, ahead does not, equal does not.

Run: python3 tools/progress_tree_freshness_devtest.py   (exit 0 = pass)
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROG = ROOT / "tools" / "progress.py"


def _git(cwd, *args, check=True):
    r = subprocess.run(("git",) + args, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise AssertionError(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


def _fixture():
    """An origin repo with one ticket, and a clone whose HEAD equals it."""
    d = pathlib.Path(tempfile.mkdtemp())
    origin, clone = d / "origin", d / "clone"
    origin.mkdir()
    _git(origin, "init", "--quiet", "-b", "master")
    _git(origin, "config", "user.email", "t@example.invalid")
    _git(origin, "config", "user.name", "t")
    tix = origin / "devdocs" / "progress" / "backlog"
    tix.mkdir(parents=True)
    (tix / "demo-row.md").write_text(
        "---\nslug: demo-row\ntrack: A\nprio: 45\ntype: feature\n"
        'status: backlog\nblocked-by: []\nowner: someone\nsummary: "a row."\n'
        "---\n\n# demo-row\n")
    _git(origin, "add", "-A")
    _git(origin, "commit", "--quiet", "-m", "first")
    _git(d, "clone", "--quiet", str(origin), str(clone))
    _git(clone, "config", "user.email", "t@example.invalid")
    _git(clone, "config", "user.name", "t")
    (clone / "tools").mkdir(exist_ok=True)
    (clone / "tools" / "progress.py").write_text(
        PROG.read_text(encoding="utf-8"), encoding="utf-8")
    return origin, clone


def _check(clone):
    r = subprocess.run([sys.executable, str(clone / "tools" / "progress.py"), "check"],
                       cwd=clone, capture_output=True, text=True)
    return r.stdout + r.stderr


def _commit_on(repo, name):
    p = repo / "devdocs" / "progress" / "backlog" / f"{name}.md"
    p.write_text(
        f"---\nslug: {name}\ntrack: A\nprio: 45\ntype: feature\n"
        f'status: backlog\nblocked-by: []\nowner: someone\nsummary: "a row."\n'
        f"---\n\n# {name}\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", name)


def case_a_BEHIND_tree_is_reported_with_a_count():
    origin, clone = _fixture()
    _commit_on(origin, "later-row")
    _commit_on(origin, "later-row-two")
    out = _check(clone)
    assert "TREE-IS-BEHIND" in out, out[-900:]
    assert "2 commit(s) behind" in out, out[-900:]
    return "two commits on origin are named with the count"


def case_CONTROL_a_tree_EQUAL_to_origin_is_silent():
    origin, clone = _fixture()
    out = _check(clone)
    assert "TREE-IS-BEHIND" not in out, "fired on a tree that is at origin"
    return "a tree equal to origin/master is not reported"


def case_CONTROL_a_tree_merely_AHEAD_is_silent():
    # THE ONE THAT KEEPS THE FINDING READABLE. Local commits not yet pushed is
    # the normal mid-work state of every session in the fleet. A finding that
    # fires there fires on everyone, always, and is scrolled past within a day.
    origin, clone = _fixture()
    _commit_on(clone, "my-local-row")
    _commit_on(clone, "my-second-local-row")
    out = _check(clone)
    assert "TREE-IS-BEHIND" not in out, (
        "fired on a tree that is AHEAD of origin -- unpushed work is the normal "
        "mid-work state and reporting it trains everyone to ignore the finding")
    return "unpushed local commits are not reported as staleness"


def case_DIVERGED_reports_only_the_behind_side():
    # Both directions at once: two on origin, one local. The behind count is 2
    # and the local commit must not change it.
    origin, clone = _fixture()
    _commit_on(origin, "theirs-one")
    _commit_on(origin, "theirs-two")
    _commit_on(clone, "mine-one")
    out = _check(clone)
    assert "TREE-IS-BEHIND" in out, out[-900:]
    assert "2 commit(s) behind" in out, out[-900:]
    return "a diverged tree reports the behind side only, uninflated by local work"


def case_an_UNREACHABLE_origin_says_so_rather_than_reading_as_clean():
    # An unreachable origin and an up-to-date tree produce the same silence, and
    # only one of them means the findings are about today.
    origin, clone = _fixture()
    _git(clone, "remote", "set-url", "origin",
         str(clone.parent / "there-is-no-repo-here"))
    out = _check(clone)
    assert "TREE-FRESHNESS-UNKNOWN" in out, out[-900:]
    assert "TREE-IS-BEHIND" not in out, "claimed a distance it could not measure"
    return "a failed fetch is reported, not silently treated as up to date"


CASES = [case_a_BEHIND_tree_is_reported_with_a_count,
         case_CONTROL_a_tree_EQUAL_to_origin_is_silent,
         case_CONTROL_a_tree_merely_AHEAD_is_silent,
         case_DIVERGED_reports_only_the_behind_side,
         case_an_UNREACHABLE_origin_says_so_rather_than_reading_as_clean]


def main():
    rc = 0
    for c in CASES:
        name = c.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = c()
        except Exception as e:                  # noqa: BLE001 - report, continue
            print(f"  FAIL {name}: {type(e).__name__}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("tree-freshness OK" if rc == 0 else "tree-freshness BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
