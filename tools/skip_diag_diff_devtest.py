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
# What the runner writes when the compile produced no diagnostic at all --
# a fact about the RUN, never about the row.
NOTFOUND = "<compile failed with no error: line> sh: 1: pascal26: not found"


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


def case_the_tgenfunc8_shape_SAME_line_different_message_is_caught():
    # THE ROW THAT SETTLES THE NORMALISATION QUESTION. frankS measured 86 shared
    # rows across two sweeps: 81 identical, 5 differed, ZERO pure line-number
    # churn. tgenfunc8 differed at the SAME line 26 with a different message --
    # so a tool that keyed on the line number, or on any positional key, would
    # call this row unchanged. It is here as a devtest so that a future
    # "normalise away the line numbers" change has to break a named test.
    out, _ = _run(
        _map([("tgenfunc8", "pascal26:26: error: undefined variable (SpecHelper)")]),
        _map([("tgenfunc8", "pascal26:26: error: generic function has no body")]))
    assert "MOVED: 1" in out, "keyed on the line and missed a message change:\n" + out
    return "a message change at an unchanged line number is still a move"


def case_a_LINE_MOVE_within_a_fixed_file_is_a_move():
    # The other end of the same measurement: tarray3 went 13 -> 129. Corpus
    # sources are FIXED, so a line only moves when the compiler starts failing
    # at a different POINT -- a mechanism change, and the signal wanted.
    out, _ = _run(_map([("tarray3", "pascal26:13: error: type mismatch")]),
                  _map([("tarray3", "pascal26:129: error: type mismatch")]))
    assert "MOVED: 1" in out, "stripped the line number and went blind:\n" + out
    return "the same message at a different line is a move (fixed sources)"


def case_a_move_into_a_RUN_FAILURE_value_is_marked_not_silently_a_diagnostic():
    out, _ = _run(_map([("tmoperator9", WAS)]),
                  _map([("tmoperator9", NOTFOUND)]))
    assert "MOVED: 1" in out, out
    assert "NOT A DIAGNOSTIC" in out, (
        "an environment failure entered the report as a mechanism change:\n" + out)
    return "a row that stopped producing a diagnostic is reported but marked"


def case_EVERY_row_moving_into_a_run_failure_is_called_a_broken_run():
    # frankS's rc=127 sweep, in miniature: the fpc side wrote its binaries
    # elsewhere and every row came back with no diagnostic. Read row-by-row that
    # is "all your mechanisms changed"; read as a shape it is one broken run.
    out, _ = _run(_map([("tmoperator9", WAS), ("tgeneric78", WAS), ("tarray3", WAS)]),
                  _map([("tmoperator9", NOTFOUND), ("tgeneric78", NOTFOUND),
                        ("tarray3", NOTFOUND)]))
    assert "BROKEN RUN" in out, "read a broken run as three changed mechanisms:\n" + out
    return "all-rows-unmeasured is reported as a broken run, not as staleness"


def case_CONTROL_a_MIXED_run_is_not_called_broken():
    # THE CONTROL THAT KEEPS THE ABOVE HONEST. One row genuinely moved and one
    # went unmeasured: the run produced real diagnostics, so the "broken run"
    # sentence would be false and would train a reader to ignore it.
    out, _ = _run(_map([("tmoperator9", WAS), ("tgeneric78", WAS)]),
                  _map([("tmoperator9", NOW), ("tgeneric78", NOTFOUND)]))
    assert "MOVED: 2" in out, out
    assert "BROKEN RUN" not in out, (
        "called a run broken while it was still producing diagnostics:\n" + out)
    assert "NOT A DIAGNOSTIC" in out, "lost the per-row mark:\n" + out
    return "a run that still diagnoses is not called broken"


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
         case_the_tgenfunc8_shape_SAME_line_different_message_is_caught,
         case_a_LINE_MOVE_within_a_fixed_file_is_a_move,
         case_a_move_into_a_RUN_FAILURE_value_is_marked_not_silently_a_diagnostic,
         case_EVERY_row_moving_into_a_run_failure_is_called_a_broken_run,
         case_CONTROL_a_MIXED_run_is_not_called_broken,
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
