#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: nothing new may read tstate straight out of a working tree.

task-t-worktree-is-not-current-state. A watcher clone is DETACHED at the sha
under test for most of every cycle, so its worktree is a point-in-time snapshot:

  * newer `tstate/reports/*.md` do not exist there yet
  * `<host>.json` holds that sha's verdicts, not today's
  * file mtimes are rewritten by every checkout

Four separate bugs in one day came from reading it, two of them in shipped
tools — and the fourth REPRODUCED the second a few hours after that one was
fixed, in a different tool. Knowing the rule was not enough; nothing enforced
it. This is the enforcement: a new tool that joins a clone path with the tstate
directory has to either route through the shared helper or state its reason
here, in review, rather than discovering the rule from a false alert weeks
later.

Run: python3 tools/tstate_reader_devtest.py
"""
import os
import pathlib
import re
import sys

TOOLS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import twatch  # noqa: E402

# Files allowed to touch tstate by filesystem path, and WHY. Adding a name here
# is a deliberate act; the point of the list is that it is short and argued.
ALLOWED = {
    "twatch.py":
        "the WRITER — it publishes tstate, and owns states_at/materialize_tstate",
    "twatch_web.py":
        "routes through current_tstate_dir(), which reads the ref when detached",
    "trackt.py":
        "materialises host json from origin/master itself; its runs-*.ndjson "
        "tail is a DELIBERATE worktree read (the live view wants rows as they "
        "are appended, before the publish that would put them on the ref)",
    "tstate_stats.py":
        "runs from a dev checkout on a branch, never from the watcher clone",
    "tstate_reader_devtest.py": "this file",
    "vanish.py":
        "a WRITER, and only under --publish: it writes tstate/vanished.md and "
        "reads nothing there. Runs from a dev checkout on a branch, never from "
        "the watcher clone — same category as uforth_bench.py",
    "twatch_code_stamp_devtest.py":
        "joins TSTATE_REL onto a tempfile dir it just created, so a fixture "
        "host json has somewhere to live; it never opens the repo's tstate. "
        "Same fixture case as the three twatch_* entries below",
    "pasmith_ledger_throttle_devtest.py":
        "reads the LIVE published fuzz/LEDGER.json ON PURPOSE, read-only, and "
        "skips when it is absent. That is the point of the guard it carries: a "
        "fixture cannot notice a schema drift in the real file, and the number "
        "a human reads is the real one",
    "uforth_bench.py":
        "a WRITER — appends bench rows, and runs from a dev checkout on a "
        "branch, never from the watcher clone",
    "twatch_pin_baseline_devtest.py":
        "joins TSTATE_REL onto a tempfile.mkdtemp() it just created, to give "
        "the shadow somewhere to append pin-shadow.log; it never reads the "
        "repo's tstate at all",
    "twatch_close_stubs_devtest.py":
        "builds its own throwaway clone as a fixture; the path it joins is the "
        "fixture's, not a live watcher's",
    "twatch_failing_step_devtest.py":
        "same fixture case: it git-inits a bare repo plus a clone under "
        "tempfile and joins TSTATE_REL onto THAT, so file_stub_tickets has a "
        "real tree to publish into. It never opens the repo's own tstate",
    # Same case as the line above, verified one at a time rather than waved
    # through as a group: each of these joins tstate onto a root/clone/path IT
    # JUST CREATED under tempfile, so there is no live watcher tree to be stale
    # about. A devtest that could not build its own tstate fixture could not
    # test the readers at all.
    "twatch_job_history_devtest.py":
        "same fixture case: repo_with() makes a tempfile.mkdtemp() and joins "
        "TSTATE_REL onto THAT to write the runs-<host>.ndjson and state file "
        "the query is tested against. It never opens the repo's own tstate — "
        "which matters here more than usual, since the whole subject of the "
        "test is a query returning the wrong answer from the right file",
    "devtest_pin_shadow.py":
        "joins TSTATE_REL onto the throwaway root it makes at line 46",
    "devtest_pin_verify.py":
        "joins TSTATE_REL onto its own fixture clone (make_repo/FakeClone)",
    "devtest_pinstatus.py":
        "os.makedirs on its own tempdir's devdocs/progress/tstate",
    "devtest_wedge_on_own_writes.py":
        "joins TSTATE_REL onto the fixture clone it creates at line 66",
    "twatch_timeout_verdict_devtest.py":
        "joins TSTATE_REL onto a tempfile.mkdtemp() it just made, so "
        "write_report_md has a reports/ dir to write into; it never touches "
        "the repo's tstate",
    "twatch_covering_devtest.py":
        "builds a whole throwaway git repo under tempfile and writes a "
        "runs-box.ndjson fixture into its tstate; it asserts on that fixture "
        "and never opens the checkout's own archive — deliberately, since the "
        "live one grows every few minutes and an assertion about its contents "
        "would pass or fail on its own",
    "twatch_verify_request_devtest.py":
        "builds a throwaway git repo under tempfile and writes both the "
        "request queue and a runs-box.ndjson fixture into ITS tstate; it "
        "asserts on that fixture and never opens the checkout's own",
    # The three below became VISIBLE to this guard on 2026-08-31, when the
    # positive control forced PATH_JOIN to cover `Path(x) / TSTATE_REL`. They
    # are not new files and they were never exempt -- the detector simply could
    # not see the idiom they use, so they had been slipping the sweep for as
    # long as they have existed. Categorised by reading each one, not waved
    # through: in all three the mkdtemp is the line immediately above the join.
    "twatch_clone_clean_devtest.py":
        "same fixture case: mkdtemp at line 38, then (tmp / TSTATE_REL) at 39 "
        "to plant an xeon.json; line 58 reads back out of the FakeClone's own "
        "path, never the checkout's",
    "twatch_host_epoch_devtest.py":
        "same fixture case: mkdtemp at line 38, join at 39; lines 56/67 join "
        "TSTATE_REL onto clone.path, which is that fixture's clone. Line 52 is "
        "an assertion about the CONSTANT's shape and opens nothing",
    "twatch_quiet_host_devtest.py":
        "same fixture case: mkdtemp at line 68 and the join at 69, so "
        "regen_index has a scratch tstate to write TSTATE.md into; it reads "
        "back only what it just generated",
    "trackt_remote_health_devtest.py":
        "same fixture case: make_repo() joins TSTATE_REL onto the "
        "TemporaryDirectory() it was handed (line 39) and writes its own "
        "runs-<host>.ndjson rows there. It never opens the repo's archive -- "
        "which is load-bearing here rather than incidental, because the code "
        "under test picks the NEWEST published verdict across hosts and "
        "compares its age to a threshold; against the live archive the "
        "assertions would pass or fail on what the watcher happened to publish "
        "in the last hour",
    "twatch_cascade_qualifier_devtest.py":
        "same fixture case: make_repo() git-inits a repo under tempfile (line "
        "45) and commits a docs/tstate-only change and a compiler/ one, so "
        "bad_qualifier has real shas of each shape to classify. The tstate "
        "path it writes is that fixture's, never the checkout's",
    "autotriage.py":
        "reads tstate off the REF by default (git show origin/master:...) — the "
        "path join remains only for the explicit `--rev ''` worktree opt-in, "
        "which a dev checkout needs for tstate it has not pushed yet",
}

# Only real path CONSTRUCTION counts. Prose matters — testmgr.py discusses
# tstate at length in its comments and touches none of it — so a bare mention
# must not trip this, or the guard gets muted as noisy, which is how enforcement
# dies.
# The second alternative was added 2026-08-31 because the positive control
# below caught its absence on the control's FIRST run: `Path(clone) / TSTATE_REL`
# put TSTATE outside the parens, so the pathlib-division idiom -- the natural one
# in any file already using Path -- was invisible to the sweep. Uppercase is
# deliberate; it keeps prose mentioning devdocs/progress/tstate from tripping.
PATH_JOIN = re.compile(
    r"(?:os\.path\.join|Path)\s*\([^)]*(?:TSTATE|devdocs/progress/tstate)"
    r"|/\s*(?:\w+\.)?TSTATE\w*", re.S)


def case_no_unlisted_tool_reads_tstate_by_path():
    offenders = []
    for py in sorted(TOOLS.glob("*.py")):
        if py.name in ALLOWED:
            continue
        text = py.read_text(encoding="utf-8", errors="replace")
        if PATH_JOIN.search(text):
            offenders.append(py.name)
    assert not offenders, (
        "these read tstate by filesystem path and are not in ALLOWED: %s — "
        "route them through twatch.materialize_tstate()/states_at(), or add "
        "them to ALLOWED with the reason" % ", ".join(offenders))
    return f"{len(ALLOWED)} allowed, all argued"


def case_the_detector_can_still_fail():
    """POSITIVE CONTROL for the sweep above, which is the case that can rot.

    `case_no_unlisted_tool_reads_tstate_by_path` asserts an EMPTY offender list.
    That assertion passes just as cleanly when PATH_JOIN has stopped matching
    anything at all -- a tightened regex, a renamed constant, a refactor that
    moves the join behind a helper -- and it would go on printing PASS while
    enforcing nothing. A guard that cannot fail is not a guard.

    It has fired for real (2026-08-31, on two devtests added that morning), but
    "it fired once" is history, not a property. So pin the detector's BOTH
    directions against literals, here, where a change to PATH_JOIN has to face
    them.
    """
    must_match = [
        'tdir = os.path.join(tmp, twatch.TSTATE_REL)',
        'p = os.path.join(root, "devdocs/progress/tstate", name)',
        'Path(clone) / TSTATE_REL',
    ]
    for src in must_match:
        assert PATH_JOIN.search(src), \
            "PATH_JOIN no longer detects a real tstate path join: %r — the "\
            "sweep above is now vacuous and will keep reporting PASS" % src
    must_not_match = [
        '# testmgr discusses devdocs/progress/tstate at length in comments',
        'print("see devdocs/progress/tstate for the archive")',
    ]
    for src in must_not_match:
        assert not PATH_JOIN.search(src), \
            "PATH_JOIN now trips on prose (%r) — a noisy guard gets muted, "\
            "which is how enforcement dies" % src
    return "%d joins detected, %d prose mentions ignored" % (
        len(must_match), len(must_not_match))


def case_the_shared_helper_exists_and_is_whole():
    """`states_at` covers host json only; the dashboard also needs reports/ and
    the tsv files, which is why materialize_tstate brings the whole subtree —
    otherwise the next reader writes its own and gets it wrong again."""
    for name in ("states_at", "materialize_tstate", "head_detached"):
        assert hasattr(twatch, name), f"twatch.{name} is gone"
    root = twatch.materialize_tstate(str(TOOLS.parent))
    assert root, "could not materialise tstate from origin/master"
    tdir = pathlib.Path(root) / twatch.TSTATE_REL
    got = {p.name for p in tdir.iterdir()}
    for needed in ("reports", "bench.tsv", "conformance.tsv"):
        assert needed in got, f"materialised tree is missing {needed}: {sorted(got)}"
    assert any(p.name.endswith(".json") for p in tdir.iterdir()), \
        "no host state files in the materialised tree"
    return f"{len(got)} entries incl. reports/ and the tsv files"


def case_detachment_is_detected():
    """The whole rule turns on this predicate, so pin BOTH directions.

    This used to assert `head_detached(this repo) is False` — a true fact about
    the wrong subject. It measured "the checkout I happen to be running in is on
    a branch", not "the predicate distinguishes the two states", and the one
    environment where it matters is a WATCHER CLONE, which is detached at the
    sha under test by design. So the full tier failed `tools-devtest` every time
    it ran, on a test whose subject was the runner rather than the code, while
    passing in every dev checkout. It also never exercised the True direction at
    all, which is the direction the entire rule is built on.

    A scratch repo answers the actual question and answers it anywhere.
    """
    import subprocess
    import tempfile

    with tempfile.TemporaryDirectory(prefix="tstate-detach-") as d:
        def git(*a):
            subprocess.run(("git",) + a, cwd=d, check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        git("init", "-q", "-b", "main")
        git("config", "user.email", "t@example.invalid")
        git("config", "user.name", "t")
        pathlib.Path(d, "f").write_text("x\n")
        git("add", "f")
        git("commit", "-qm", "one")
        assert twatch.head_detached(d) is False, \
            "a checkout on a branch was reported as detached"
        sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=d, check=True,
                             capture_output=True, text=True).stdout.strip()
        git("checkout", "-q", sha)
        assert twatch.head_detached(d) is True, \
            "a DETACHED checkout was reported as on a branch — the rule this "\
            "whole file enforces would then never fire in a watcher clone"
    return "branch -> False, detached -> True (scratch repo, not this checkout)"


def case_helper_falls_back_rather_than_raising():
    """A repo with no tstate on the ref (fresh clone, no remote) must return
    None so the caller can fall back deliberately — never explode, and never
    silently hand back an empty directory that reads as 'no state'."""
    assert twatch.materialize_tstate("/", ref="origin/master") is None
    assert twatch.materialize_tstate(str(TOOLS.parent), ref="refs/heads/no-such") is None
    return "missing ref / non-repo -> None"


CASES = [
    case_no_unlisted_tool_reads_tstate_by_path,
    case_the_detector_can_still_fail,
    case_the_shared_helper_exists_and_is_whole,
    case_detachment_is_detected,
    case_helper_falls_back_rather_than_raising,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = case()
        except AssertionError as e:
            print(f"  FAIL {name}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("tstate reader discipline OK" if rc == 0
          else "tstate reader discipline BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
