#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: STALE-PARK's `PARK CONDITION SUPERSEDED` marker is WINDOW-scoped.

Why the escape exists (frankS, 2026-09-06): the flag fired correctly on a park
whose 2026-07-10 resume condition was "needs sole-A confirmation", a thing this
repo no longer has. Marking it superseded in place made the flag name FIVE slugs
instead of four, because park prose LEGITIMATELY cites resolved tickets as
HISTORY and the check cannot tell a live resume condition from a record of one
that was lifted. Rewriting history to satisfy a lint is the wrong move, so the
lint learns instead.

THE CASES THAT MATTER ARE THE ONES WHERE IT MUST NOT FIRE. An escape that
silences everything and an escape that silences the right thing produce the same
clean run, so a marker two blocks away and a second still-live condition in the
same ticket are asserted to STILL flag. Without those, this file would pass just
as happily over a whole-ticket escape, which is the over-reach the window scope
exists to avoid.

Run: python3 tools/park_superseded_devtest.py   (exit 0 = pass)
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROG = ROOT / "tools" / "progress.py"

CLOSED_A = "bug-t-a-closed-blocker-fixture-row"
CLOSED_B = "bug-t-a-second-closed-blocker-fixture"
PARKED = "feature-t-the-parked-fixture-row"


def _tree(body):
    """A scratch progress tree: one parked ticket with `body`, two closed rows."""
    d = pathlib.Path(tempfile.mkdtemp())
    prog = d / "devdocs" / "progress"
    for folder, slug, status in (("done", CLOSED_A, "done"),
                                 ("done", CLOSED_B, "done"),
                                 ("unfinished", PARKED, "unfinished")):
        p = prog / folder
        p.mkdir(parents=True, exist_ok=True)
        text = "\n".join([
            "---", f"slug: {slug}", "track: T", "prio: 30", "type: feature",
            f"status: {status}", "blocked-by: []", 'owner: ""',
            'summary: "a fixture row."', "---", "",
        ])
        text += body if slug == PARKED else f"# {slug}\n"
        (p / f"{slug}.md").write_text(text, encoding="utf-8")
    return d


def _flagged(out):
    """True if a STALE-PARK flag names the fixture ticket.

    NOT a bare `"STALE-PARK" in out`: `check` prints an explanatory NOTE naming
    STALE-PARK on EVERY run, so the substring is always present and the negative
    assertion can never fail. Cost this file one red before it was noticed --
    the same shape as a banner absorbing the word a test was looking for.
    """
    return any(ln.startswith(("STALE-PARK:", "STALE-PARK-HELD:")) and PARKED in ln
               for ln in out.splitlines())


def _check(tree):
    tools = tree / "tools"
    tools.mkdir(exist_ok=True)
    (tools / "progress.py").write_text(PROG.read_text(encoding="utf-8"), encoding="utf-8")
    r = subprocess.run([sys.executable, str(tools / "progress.py"), "check"],
                       cwd=tree, capture_output=True, text=True)
    return r.stdout + r.stderr


FILLER = "\nsome unrelated prose that names no ticket.\n" * 6


def case_CONTROL_a_live_park_condition_still_flags():
    """The negative control for every case below. Without it they prove nothing."""
    out = _check(_tree(f"# fixture\n\nBlocked on [[{CLOSED_A}]].\n"))
    assert _flagged(out), out[-900:]
    assert CLOSED_A in out, out[-900:]
    return "an unmarked park block with a resolved citation is reported"


def case_the_marker_inside_the_window_silences_that_block():
    out = _check(_tree(
        f"# fixture\n\nPARK CONDITION SUPERSEDED -- kept as history.\n"
        f"Blocked on [[{CLOSED_A}]].\n"))
    assert not _flagged(out), "the marker did not silence its own block\n" + out[-900:]
    return "a marked block stops being reported"


def case_the_marker_TWO_BLOCKS_AWAY_does_NOT_reach():
    """Window-scoped, not ticket-scoped: the marker must sit beside what it excuses."""
    out = _check(_tree(
        f"# fixture\n\nPARK CONDITION SUPERSEDED -- an old note about something else.\n"
        f"{FILLER}\nBlocked on [[{CLOSED_A}]].\n"))
    assert _flagged(out), (
        "a marker eight lines away silenced the block -- the escape has become "
        "ticket-scoped and will hide a stale condition added months later\n" + out[-900:])
    return "a distant marker does not excuse an unrelated block"


def case_a_SECOND_live_condition_still_flags_when_the_first_is_excused():
    """The whole point of window scope: one excused block must not cover the ticket."""
    out = _check(_tree(
        f"# fixture\n\nPARK CONDITION SUPERSEDED -- history.\nBlocked on [[{CLOSED_A}]].\n"
        f"{FILLER}\nBlocked on [[{CLOSED_B}]].\n"))
    assert _flagged(out), (
        "excusing one block silenced the whole ticket\n" + out[-900:])
    assert CLOSED_B in out, "the still-live condition was not the one named\n" + out[-900:]
    return "a second, unmarked condition in the same ticket still fires"


def main():
    cases = [v for k, v in sorted(globals().items()) if k.startswith("case_")]
    bad = 0
    for fn in cases:
        try:
            print(f"PASS  {fn.__name__} -- {fn()}")
        except AssertionError as e:
            bad += 1
            print(f"FAIL  {fn.__name__}\n      {e}")
    print(f"\n{len(cases) - bad}/{len(cases)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
