#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the case-registration lint can SEE both case-naming conventions.

THE GUARD THAT HAD NO APERTURE OVER 20 OF THE FILES IT POLICES.

`devtest_case_registration.py` asserts that every case a harness defines is also
run. It knew only the `t_*` convention. Twenty harnesses name their cases
`case_*`, so for those files it found zero cases, `main()` skipped them, and the
denominator lost them without a sound: `OK -- 404 case(s) across 45 harness(es)`
is a true sentence about a population that excludes the files in question. That
is verbatim the failure the lint's own docstring is about -- *"a count missing a
member reads exactly like a count of everything"* -- committed by the count that
names it.

**An aperture defect cannot be caught by the guard's own output**, because the
output is correct about what it saw. It can only be caught by a fixture the guard
must be able to see. So the cases below are POSITIVE CONTROLS in the strict
sense: each hands the lint a harness with a known planted defect, in a specific
convention, and fails if the lint reports OK. **Ablation RUN, not asserted:**
narrowing `CASE_PREFIXES` back to `("t_",)` and re-running turns 4 of these 6
rows red, all with `NO HARNESSES MATCHED`. That is the whole point of the file --
a guard for a guard is worthless unless someone has watched it fail.

The negative control matters as much: a correctly registered harness in either
convention must come back clean, or the lint is a check that flags everything.

This harness deliberately uses the `case_*` convention itself.

Run: python3 tools/devtest_registration_aperture_devtest.py   (exit 0 = pass)
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
LINT = ROOT / "tools" / "devtest_case_registration.py"

REGISTERED = """\
def {p}alpha():
    return 1


def {p}beta():
    return 2


CASES = [{p}alpha, {p}beta]


def main():
    for c in CASES:
        c()
"""

UNREGISTERED = """\
def {p}alpha():
    return 1


def {p}orphan():
    return 2


CASES = [{p}alpha]


def main():
    for c in CASES:
        c()
"""


def _harness(body, prefix):
    d = pathlib.Path(tempfile.mkdtemp())
    f = d / "fixture_devtest.py"
    f.write_text(body.format(p=prefix))
    return f


def _run(*paths):
    r = subprocess.run([sys.executable, str(LINT)] + [str(p) for p in paths],
                       capture_output=True, text=True)
    return r.stdout + r.stderr, r.returncode


def case_the_t_convention_is_seen():
    out, rc = _run(_harness(UNREGISTERED, "t_"))
    assert rc == 1, "missed an unregistered t_ case:\n" + out
    assert "t_orphan" in out, out
    return "an unrun t_ case is reported"


def case_the_case_convention_is_seen_THE_APERTURE_THAT_WAS_MISSING():
    # THE ROW THIS FILE EXISTS FOR. Twenty real harnesses are shaped like this
    # fixture. Before 2026-09-06 the lint answered NO HARNESSES MATCHED here and
    # answered OK in aggregate, which is the same silence.
    out, rc = _run(_harness(UNREGISTERED, "case_"))
    assert rc == 1, (
        "an unregistered case_* case was invisible -- this is the exact aperture "
        "defect the lint was blind to for its whole life:\n" + out)
    assert "case_orphan" in out, out
    return "an unrun case_ case is reported"


def case_CONTROL_a_registered_t_harness_is_clean():
    out, rc = _run(_harness(REGISTERED, "t_"))
    assert rc == 0, "flagged a correctly registered harness:\n" + out
    return "a fully registered t_ harness passes"


def case_CONTROL_a_registered_case_harness_is_clean():
    # Without this, widening the prefixes could be "fixed" by flagging everything,
    # and a guard that flags everything is as empty as one that never fires.
    out, rc = _run(_harness(REGISTERED, "case_"))
    assert rc == 0, "flagged a correctly registered case_ harness:\n" + out
    assert "2 case(s)" in out, "counted the wrong number of cases:\n" + out
    return "a fully registered case_ harness passes, with both cases counted"


def case_a_file_with_NO_recognised_cases_is_COUNTED_not_silently_dropped():
    # The mechanism of the original defect: a file the lint cannot read leaves the
    # denominator with no sound at all. It must be counted and printed, so that a
    # THIRD convention arriving tomorrow makes a number move instead of hiding.
    # Paired with a real harness on purpose: a lone unreadable file is a genuinely
    # empty population and the lint correctly refuses that. The defect being
    # guarded is the MIXED run, where one unreadable file rides along invisibly
    # beside files that answer -- which is what the aggregate glob run is.
    blind = _harness("def helper_alpha():\n    return 1\n", "unused_")
    real = _harness(REGISTERED, "case_")
    out, rc = _run(real, blind)
    assert rc == 0, out
    assert "defined no case under them" in out, out
    assert "1 file(s)" in out, "did not count the file it could not read:\n" + out
    return "an unreadable file riding beside a real harness is counted, not dropped"


def case_the_prefixes_in_use_are_NAMED_in_the_output():
    # A reader cannot tell which conventions were audited from a count. Naming
    # them is what makes the aperture checkable without reading the source.
    out, _ = _run(_harness(REGISTERED, "case_"))
    assert "prefixes audited" in out and "t_/case_" in out, out
    return "the audited prefixes are printed, not left implicit"


CASES = [case_the_t_convention_is_seen,
         case_the_case_convention_is_seen_THE_APERTURE_THAT_WAS_MISSING,
         case_CONTROL_a_registered_t_harness_is_clean,
         case_CONTROL_a_registered_case_harness_is_clean,
         case_a_file_with_NO_recognised_cases_is_COUNTED_not_silently_dropped,
         case_the_prefixes_in_use_are_NAMED_in_the_output]


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
    print("registration-aperture OK" if rc == 0 else "registration-aperture BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
