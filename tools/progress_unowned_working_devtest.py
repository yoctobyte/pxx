#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: `check` reports a ticket in working/ with no owner.

`working/` asserts somebody is on it, so `ready`/`next` do not offer it.
`owner:` empty means nothing attributes it. **That combination is invisible in
both directions** — missing from the offered queue AND from every "who holds
what" answer, including a coordinator's holdings report — and it reads to a
human as a row somebody parked and forgot.

Found 2026-09-06 when one such row turned up (`feature-dynamic-compiler-tables`,
the topic a session had been converting all night without claiming). The census
that followed found 4 of 23 in working/, which is a shape rather than a slip.

THE CONTROL THAT MATTERS IS THE NEGATIVE ONE. `park` CLEARS the owner by design,
so an empty owner in unfinished/ or blocked/ is the CORRECT record of "nobody is
on this" — 11 of 21 and 4 of 7 respectively on the day this was written, every
one of them right. A check that flagged those would be reporting the tool's own
documented behaviour as a defect, and would be scrolled past within a day.

Run: python3 tools/progress_unowned_working_devtest.py   (exit 0 = pass)
"""
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROG = ROOT / "tools" / "progress.py"


def _tree(rows):
    """A scratch progress tree: rows are (folder, slug, owner-or-None)."""
    d = pathlib.Path(tempfile.mkdtemp())
    for folder, slug, owner in rows:
        p = d / "devdocs" / "progress" / folder
        p.mkdir(parents=True, exist_ok=True)
        fm = ["---", f"slug: {slug}", "track: A", "prio: 45", "type: feature",
              f"status: {folder}", "blocked-by: []"]
        if owner is not None:
            fm.append(f"owner: {owner}")
        fm += ['summary: "a row."', "---", "", f"# {slug}", ""]
        (p / f"{slug}.md").write_text("\n".join(fm))
    return d


def _check(tree):
    src = PROG.read_text(encoding="utf-8")
    tools = tree / "tools"
    tools.mkdir(exist_ok=True)
    (tools / "progress.py").write_text(src, encoding="utf-8")
    r = subprocess.run([sys.executable, str(tools / "progress.py"), "check"],
                       cwd=tree, capture_output=True, text=True)
    return r.stdout + r.stderr


def case_an_unowned_working_row_is_reported():
    out = _check(_tree([("working", "demo-unowned", None)]))
    assert "UNOWNED-IN-WORKING" in out, out[-800:]
    assert "demo-unowned" in out, out[-800:]
    return "a working/ row with no owner is named"


def case_an_empty_owner_string_counts_as_unowned():
    # `owner: ""` and `owner:` are the same board state and must not differ.
    out = _check(_tree([("working", "demo-blank", '""')]))
    assert "UNOWNED-IN-WORKING" in out, out[-800:]
    return 'owner: "" is treated as unowned, same as a missing key'


def case_CONTROL_an_owned_working_row_is_silent():
    out = _check(_tree([("working", "demo-held", "frankB")]))
    assert "UNOWNED-IN-WORKING" not in out, "fired on a properly owned row"
    return "an owned working/ row is not reported"


def case_CONTROL_park_clears_the_owner_and_that_is_correct():
    # THE ONE THAT KEEPS THE CHECK READABLE. `park` clears owner by design, so
    # unfinished/ and blocked/ are full of legitimately unowned rows. Reporting
    # them would be reporting the tool's own documented behaviour as a defect.
    out = _check(_tree([("unfinished", "demo-parked", None),
                        ("blocked", "demo-gated", None)]))
    assert "UNOWNED-IN-WORKING" not in out, (
        "fired on unfinished/ or blocked/, where an empty owner is what `park` "
        "writes on purpose")
    return "unowned rows in unfinished/ and blocked/ are correct and silent"


def case_it_reports_ONCE_with_a_list_not_once_per_row():
    # A twelve-line explanation repeated per row is the shape that earns the
    # habit of being scrolled past; the explanation is identical every time and
    # only the list differs.
    out = _check(_tree([("working", "demo-a", None),
                        ("working", "demo-b", None),
                        ("working", "demo-c", None)]))
    n = len(re.findall(r"UNOWNED-IN-WORKING", out))
    assert n == 1, f"emitted {n} findings for 3 rows; expected one with a list"
    for slug in ("demo-a", "demo-b", "demo-c"):
        assert slug in out, f"{slug} missing from the single finding"
    assert "3 ticket(s)" in out, out[-800:]
    return "three rows produce one finding naming all three"


CASES = [case_an_unowned_working_row_is_reported,
         case_an_empty_owner_string_counts_as_unowned,
         case_CONTROL_an_owned_working_row_is_silent,
         case_CONTROL_park_clears_the_owner_and_that_is_correct,
         case_it_reports_ONCE_with_a_list_not_once_per_row]


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
    print("unowned-in-working OK" if rc == 0 else "unowned-in-working BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
