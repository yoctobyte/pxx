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
    "uforth_bench.py":
        "a WRITER — appends bench rows, and runs from a dev checkout on a "
        "branch, never from the watcher clone",
    "twatch_close_stubs_devtest.py":
        "builds its own throwaway clone as a fixture; the path it joins is the "
        "fixture's, not a live watcher's",
    # Same case as the line above, verified one at a time rather than waved
    # through as a group: each of these joins tstate onto a root/clone/path IT
    # JUST CREATED under tempfile, so there is no live watcher tree to be stale
    # about. A devtest that could not build its own tstate fixture could not
    # test the readers at all.
    "devtest_pin_shadow.py":
        "joins TSTATE_REL onto the throwaway root it makes at line 46",
    "devtest_pin_verify.py":
        "joins TSTATE_REL onto its own fixture clone (make_repo/FakeClone)",
    "devtest_pinstatus.py":
        "os.makedirs on its own tempdir's devdocs/progress/tstate",
    "devtest_wedge_on_own_writes.py":
        "joins TSTATE_REL onto the fixture clone it creates at line 66",
    "autotriage.py":
        "reads tstate off the REF by default (git show origin/master:...) — the "
        "path join remains only for the explicit `--rev ''` worktree opt-in, "
        "which a dev checkout needs for tstate it has not pushed yet",
}

# Only real path CONSTRUCTION counts. Prose matters — testmgr.py discusses
# tstate at length in its comments and touches none of it — so a bare mention
# must not trip this, or the guard gets muted as noisy, which is how enforcement
# dies.
PATH_JOIN = re.compile(
    r"(?:os\.path\.join|Path)\s*\([^)]*(?:TSTATE|devdocs/progress/tstate)", re.S)


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
    """The whole rule turns on this predicate, and it must not report a normal
    branch checkout as detached — that would send every reader through git for
    no reason."""
    assert twatch.head_detached(str(TOOLS.parent)) is False, \
        "a checkout on a branch was reported as detached"
    return "branch checkout -> not detached"


def case_helper_falls_back_rather_than_raising():
    """A repo with no tstate on the ref (fresh clone, no remote) must return
    None so the caller can fall back deliberately — never explode, and never
    silently hand back an empty directory that reads as 'no state'."""
    assert twatch.materialize_tstate("/", ref="origin/master") is None
    assert twatch.materialize_tstate(str(TOOLS.parent), ref="refs/heads/no-such") is None
    return "missing ref / non-repo -> None"


CASES = [
    case_no_unlisted_tool_reads_tstate_by_path,
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
