#!/usr/bin/env python3
"""A REQUESTED run's archive row must name what was red.

`verify_requested()` computed `reds` and spent it on one stdout line: the
archived row said `verdict: RED` with `new_red: []` and no `still_red` at all.
Three such rows exist (2026-08-30 x2, 2026-09-06), each a verdict no reader
can check, and somebody asked for every one of them.

The PIN row carried the identical defect and was fixed on 2026-09-05; the
sibling twenty lines below it was not. `devtest_pin_verify.py` guards that
arm. This guards this one.

The half that actually bites is the READER. `job_history()` exists because a
hand-rolled archive scan returned "0 hits in 1697 runs" for a job in its 13th
red run -- correct, exhaustive and false -- and it scanned exactly the three
keys a requested row does not have. Writing `reds` without teaching the
readers the key would have moved the silence rather than ended it, so the
cases below drive the real readers over a real archive file.
"""
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch  # noqa: E402

SEL = "test-emit-obj#src:test/test_emit_obj.pas@3"
OTHER = "lib-test#src:test/lib_sysutils_delphi_exceptions.pas"

FAILED = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILED.append(what)


def archive(rows):
    """A real checkout-shaped tstate dir; the readers do their own IO."""
    d = tempfile.mkdtemp(prefix="twatch-reqreds-")
    os.makedirs(os.path.join(d, twatch.TSTATE_REL), exist_ok=True)
    with open(os.path.join(d, twatch.TSTATE_REL, "runs-seven.ndjson"), "w") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True) + "\n")
    return d


def requested_row(**over):
    r = {"sha": "5411e996794f3edaebc0791f47e588b614af6936",
         "date": "2026-09-06T19:32:19Z", "tier": "full", "full": True,
         "verdict": "RED", "wall": 600.7, "requested_by": "seven",
         "reds": [SEL]}
    r.update(over)
    return r


def case_a_requested_red_is_findable_by_job_history():
    repo = archive([requested_row()])
    hits = twatch.job_history(repo, SEL, host="seven")
    check(len(hits) == 1, "job_history finds a job red only in a requested run")
    if hits:
        check(hits[0][4] == "reds",
              "and reports the key it was found under, not a borrowed one")


def case_the_same_row_without_reds_is_invisible():
    """The positive control, drawn from the population the bug is about.

    This is the row as it was ACTUALLY written until today -- RED, empty
    new_red, no still_red. If the reader found this one too, the case above
    would pass no matter what the writer did.
    """
    repo = archive([requested_row(reds=None, new_red=[], fixed=[])])
    hits = twatch.job_history(repo, SEL, host="seven")
    check(hits == [],
          "the pre-fix row shape yields the confident zero this fixes")


def case_job_selectors_counts_it():
    repo = archive([requested_row()])
    seen = twatch.job_selectors(repo, host="seven")
    check(seen.get(SEL) == 1, "job_selectors counts a requested-run red")
    check(OTHER not in seen,
          "and does not invent selectors the row never named")


def case_the_writer_measures_rather_than_asserting():
    """AIMING check on the source, and it is one on purpose.

    `verify_requested()` runs a full tier before it writes, so there is no way
    to drive the writer here. This asserts the two things the readers above
    cannot: that the row carries the computed list, and that it does not carry
    a hardcoded empty one. Same standing as devtest_pin_verify.py's block for
    the sibling arm -- and the same known weakness, which is why the reader
    cases above are behavioural.
    """
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "twatch.py")).read()
    body = src[src.index("def verify_requested("):]
    body = body[:body.index("\ndef ")]
    check('"reds": sorted(reds)' in body,
          "the requested row records the reds it computed")
    check('"new_red": []' not in body and '"fixed": []' not in body,
          "and does not hardcode an empty new_red/fixed beside a RED verdict")
    check("reds = [job_key(j) for j in report" in body,
          "the list is still built from job_key, not a positional name")


def main():
    for fn in (case_a_requested_red_is_findable_by_job_history,
               case_the_same_row_without_reds_is_invisible,
               case_job_selectors_counts_it,
               case_the_writer_measures_rather_than_asserting):
        print(fn.__name__)
        fn()
    print()
    if FAILED:
        print("FAILED %d check(s)" % len(FAILED))
        return 1
    print("twatch requested-reds: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
