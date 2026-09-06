#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: `skip_diag_diff.py` reports a MOVED diagnostic and nothing else.

THE CONTROLS ARE THE POINT. This tool exists because an exit-code sweep is blind
to a row whose verdict is right and whose reason is wrong (see the tool's own
docstring for the five measured instances). It earns that only if MOVED means
what it says: a tool that also shouted about rows added to the skip list, or
about rows that were burned, would be read as "the skip list changed" and
scrolled past within a week -- which is the failure this repo names in as many
words, and the failure that makes a check worth less than no check.

So: a changed diagnostic fires; an identical one is silent; a NEW row and a GONE
row are reported SEPARATELY and never as MOVED; and an empty map says "nothing
was measured" rather than "nothing changed".

Run: python3 tools/skip_diag_diff_devtest.py   (exit 0 = pass)
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOL = ROOT / "tools" / "skip_diag_diff.py"

# The real thing, from the measured case: tmoperator9's reason blames record
# management operators (which work); the compile actually stops on the System
# helper that applies them over N elements.
WAS = "pascal26:12: error: undefined variable (InitializeArray)"
NOW = "pascal26:12: error: undefined variable (FinalizeArray)"


def _map(rows):
    p = pathlib.Path(tempfile.mkdtemp()) / "m.map"
    body = ["# name\tfirst-diagnostic  (run: fixture)"]
    body += [f"{n}\t{d}" for n, d in rows]
    p.write_text("\n".join(body) + "\n")
    return p


def _run(old, new, *extra):
    r = subprocess.run([sys.executable, str(TOOL), str(old), str(new), *extra],
                       capture_output=True, text=True)
    return r.stdout + r.stderr, r.returncode


def case_a_MOVED_diagnostic_is_reported_with_both_sides():
    out, rc = _run(_map([("tmoperator9", WAS)]), _map([("tmoperator9", NOW)]))
    assert "MOVED: 1" in out, out
    assert "tmoperator9" in out, out
    assert WAS in out and NOW in out, "must print both sides, not just the new one:\n" + out
    assert rc == 0, f"reports, does not gate; rc={rc}"
    return "a changed diagnostic is named with was/now"


def case_CONTROL_an_IDENTICAL_diagnostic_is_silent():
    out, _ = _run(_map([("tmoperator9", WAS)]), _map([("tmoperator9", WAS)]),
                  "--quiet-if-clean")
    assert "MOVED" not in out, "fired on a row that did not move:\n" + out
    return "an unchanged diagnostic produces no MOVED line"


def case_CONTROL_a_NEW_row_is_not_reported_as_MOVED():
    # A row added to the skip list is not a stale reason. Collapsing the two
    # would make every burn-down sweep look like a pile of staleness.
    out, _ = _run(_map([("tmoperator9", WAS)]),
                  _map([("tmoperator9", WAS), ("tgeneric78", WAS)]))
    assert "MOVED: 1" not in out, "counted an added row as moved:\n" + out
    assert "NEW: 1" in out and "tgeneric78" in out, out
    return "a row only in the new map is NEW, not MOVED"


def case_CONTROL_a_GONE_row_is_not_reported_as_MOVED():
    out, _ = _run(_map([("tmoperator9", WAS), ("tgeneric78", WAS)]),
                  _map([("tmoperator9", WAS)]))
    assert "MOVED: 1" not in out, "counted a burned row as moved:\n" + out
    assert "GONE: 1" in out and "tgeneric78" in out, out
    return "a row only in the old map is GONE, not MOVED"


def case_a_COMPILES_CLEAN_transition_is_a_move_like_any_other():
    # The runner writes "<compiles clean>" as a VALUE precisely so this row can
    # be compared. An empty field would collide with "row not attempted".
    out, _ = _run(_map([("trange5", WAS)]), _map([("trange5", "<compiles clean>")]))
    assert "MOVED: 1" in out, out
    assert "<compiles clean>" in out, out
    return "a row that started compiling clean is reported as a move"


def case_an_EMPTY_map_says_NOTHING_WAS_MEASURED_not_nothing_changed():
    empty = pathlib.Path(tempfile.mkdtemp()) / "e.map"
    empty.write_text("# name\tfirst-diagnostic\n")
    out, rc = _run(_map([("tmoperator9", WAS)]), empty)
    assert "NO ROWS" in out, out
    assert "nothing was measured" in out.lower(), out
    assert "MOVED: 1" not in out, "read an empty map as a clean comparison:\n" + out
    assert rc == 0, rc
    return "an empty map is reported as unmeasured, not as clean"


def case_a_malformed_row_is_counted_rather_than_guessed_at():
    p = pathlib.Path(tempfile.mkdtemp()) / "bad.map"
    p.write_text("# h\ntmoperator9\tx\nthis-row-has-no-tab\n")
    out, _ = _run(_map([("tmoperator9", "x")]), p)
    assert "malformed" in out.lower(), out
    assert "1 malformed" in out, out
    return "a row with no TAB is reported, not read as an empty diagnostic"


CASES = [case_a_MOVED_diagnostic_is_reported_with_both_sides,
         case_CONTROL_an_IDENTICAL_diagnostic_is_silent,
         case_CONTROL_a_NEW_row_is_not_reported_as_MOVED,
         case_CONTROL_a_GONE_row_is_not_reported_as_MOVED,
         case_a_COMPILES_CLEAN_transition_is_a_move_like_any_other,
         case_an_EMPTY_map_says_NOTHING_WAS_MEASURED_not_nothing_changed,
         case_a_malformed_row_is_counted_rather_than_guessed_at]


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
    print("skip-diag-diff OK" if rc == 0 else "skip-diag-diff BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
