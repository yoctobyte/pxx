#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a ticket fragment wearing a leftover `---` fence is an orphan.

THE INCIDENT (2026-08-31). `be154a3ca` ("board: split the backlog into per-lane
sections") split one ticket across two folders: an 88-line tail landed in
`backlog-core/` while the rest stayed in `working/`. 69 of those 88 lines
existed nowhere else, so the failure mode for anyone "tidying up the duplicate"
was silent data loss.

`NO-FRONTMATTER` read `fh.readline()` and tested `head.strip() != "---"`. The
fragment's first line WAS a bare `---` — the leftover fence from the split — so
it matched and the file passed, carrying no track, no prio, no summary and no
slug. **The check was testing the FENCE and reporting on the FRONTMATTER.**
That gap is what this file closes.

WHAT THIS FILE DELIBERATELY DOES NOT ADD, because the detour is worth more than
the code would have been: the duplicate half was ALREADY COVERED. I widened
`DUP-SLUG` to scan `working/` and `blocked/` and wrote guards for it — then the
positive-control run against the old code printed `DUPLICATE-SLUG: dup exists
in 2 status folders (backlog/, working/)`. A second check, under a second name,
found on 2026-08-30 for this exact reason, already walking every status folder.
My widening was a duplicate mechanism for a solved problem and is reverted; the
two duplicate guards below assert against the EXISTING check instead, so they
are regression coverage rather than a second implementation.

The lesson is not "the tooling missed it" — for the duplicate half the tooling
was fine and **I had simply never run `progress.sh check`.** Only the fence gap
was real.

EVERY GUARD HERE ASSERTS A FIRING, not just a clean run — the repo's own rule
that a guard which cannot fail prints PASS. `t_a_real_ticket_is_silent` is the
other half: a check that flags everything is equally useless.

Run: tools/progress_orphan_fragment_devtest.py   (exit 0 = pass)
"""
import importlib
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

pg = importlib.import_module("progress")

GOOD = {"track": "A", "prio": 50, "type": "bug", "status": "backlog"}

# The incident's fragment, reduced to its shape: a leftover fence, then prose.
ORPHAN = "---\n\n## RESULT 2026-08-31 — a section, not a ticket\n\nbody text\n"


def _tree(files):
    """A throwaway progress tree. `files` is (status, name, text)."""
    root = Path(tempfile.mkdtemp(prefix="orphan-frag-"))
    for st in pg.STATUSES:
        (root / st).mkdir(parents=True, exist_ok=True)
    (root / "done").mkdir(parents=True, exist_ok=True)
    for st, name, text in files:
        (root / st / name).write_text(text, encoding="utf-8")
    return root


def _ticket(slug, **over):
    fm = dict(GOOD)
    fm.update(over)
    return "---\n" + "\n".join("%s: %s" % kv for kv in fm.items()) + \
           "\n---\n\n# %s\n\nbody\n" % slug


def _check(files, strict=False):
    """PROG held for the WHOLE call — check() walks the filesystem itself."""
    root = _tree(files)
    old = pg.PROG
    pg.PROG = root
    try:
        b = pg.Board()
        (root / "BOARD.md").write_text(b.render_board_md(), encoding="utf-8")
        (root / "BOARD-brief.md").write_text(b.render_brief_md(),
                                             encoding="utf-8")
        for st in pg.ARCHIVED_STATUSES:
            (root / ("BOARD-%s.md" % st)).write_text(b.render_archive_md(st),
                                                     encoding="utf-8")
        return pg.Board().check(strict=strict)[1]
    finally:
        pg.PROG = old


def t_a_fence_without_a_key_is_an_orphan():
    """THE INCIDENT. Passed the old check because line 1 was '---'."""
    out = _check([("backlog", "orphan-tail.md", ORPHAN)])
    assert "NO-FRONTMATTER: backlog/orphan-tail.md" in out, out
    assert "carries no frontmatter key" in out, out
    return "a '---' with no key below it is reported"


def t_a_fragment_with_no_fence_at_all_is_still_an_orphan():
    """The older shape, still covered — this is the regression half."""
    out = _check([("backlog", "no-fence.md", "## just a heading\n\nbody\n")])
    assert "NO-FRONTMATTER: backlog/no-fence.md" in out, out
    assert "does not start with '---'" in out, out
    return "a file with no fence at all is still reported"


def t_a_ranked_and_held_duplicate_is_reported():
    """Regression coverage for the PRE-EXISTING DUPLICATE-SLUG check.

    This is the incident's other half and it was never a gap — the check has
    walked every status folder since 2026-08-30. Asserted here so the coverage
    exists, and named DUPLICATE-SLUG so nobody re-adds a second one.
    """
    out = _check([("backlog", "dup.md", _ticket("dup")),
                  ("working", "dup.md", _ticket("dup", status="working",
                                                owner="someone"))])
    assert "DUPLICATE-SLUG: dup" in out, out
    assert "working" in out and "backlog" in out, out
    return "the same slug in working/ and a ranked folder is reported"


def t_a_blocked_and_ranked_duplicate_is_reported():
    """Same, for the other lock folder."""
    out = _check([("backlog", "dup2.md", _ticket("dup2")),
                  ("blocked", "dup2.md", _ticket("dup2", status="blocked"))])
    assert "DUPLICATE-SLUG: dup2" in out, out
    return "the same slug in blocked/ and a ranked folder is reported"


def t_a_real_ticket_is_silent():
    """A check that flags everything is as useless as one that flags nothing."""
    out = _check([("backlog", "fine.md", _ticket("fine"))])
    assert "NO-FRONTMATTER" not in out, out
    assert "DUPLICATE-SLUG" not in out, out
    return "a well-formed ticket produces neither finding"


def t_a_held_ticket_alone_is_not_a_duplicate():
    """Widening the scan must not make every held ticket a finding."""
    out = _check([("working", "held.md", _ticket("held", status="working",
                                                 owner="someone"))])
    assert "DUPLICATE-SLUG" not in out, out
    return "a ticket in working/ alone is not reported"


TESTS = [t_a_fence_without_a_key_is_an_orphan,
         t_a_fragment_with_no_fence_at_all_is_still_an_orphan,
         t_a_ranked_and_held_duplicate_is_reported,
         t_a_blocked_and_ranked_duplicate_is_reported,
         t_a_real_ticket_is_silent,
         t_a_held_ticket_alone_is_not_a_duplicate]


def main():
    rc = 0
    print("orphan-fragment devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("orphan-fragment OK" if rc == 0 else "orphan-fragment BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
