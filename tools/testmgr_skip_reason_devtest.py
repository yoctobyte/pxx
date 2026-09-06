#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a skip must say WHY, and must be visible in the verdict.

`PASSLIKE = ("pass", "skip")`, so a skipped job costs a run nothing and shows
up nowhere a verdict is read. The full-tier sweep of 2026-08-26 skipped ~50 of
3081 jobs — every `test-pascal-conformance` shard, every `test-c-conformance`
shard across five targets, and every real-program corpus (lua, cjson, zlib,
fgl, fpjson, sqlite-threads) — and published `verdict: RED`, `unreached: 0`,
`timed_out: false`. Every field true. The run covered 3031 of 3081 jobs and
reported in the vocabulary of one that covered all of them, with `reason: ""`
on all fifty.

`unreached` already existed for jobs a teardown never decided, and its comment
gives exactly this reasoning. Skips were the case that got missed, and they are
the worse one: an unreached job is undecided, a skipped job is scored as fine.

FOUR ways to get this wrong; each guard says which it catches:

  * break A — a skip with no reason. The original bug.
  * break B — folding every skip into one hardcoded cause. A single
    "(corpus absent)" label described the FPC-canary skips wrongly for seven
    weeks, and a wrong reason is worse than none: it answers the question the
    reader would otherwise ask.
  * break C — counting skips BEFORE the run, so a job that skips itself during
    the run is invisible and sits in the denominator as if it had run and not
    passed.
  * break D — omitting the summary when nothing skipped, so a consumer has to
    infer from absence instead of testing a field.

Run: tools/testmgr_skip_reason_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm", os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)


class _J(object):
    """The three fields skip_summary reads."""

    def __init__(self, name, status, skip_reason=""):
        self.name = name
        self.status = status
        self.skip_reason = skip_reason


# ------------------------------------------------------------ skip_summary --

def t_summary_is_present_when_empty():
    """A consumer tests a field; it never infers from absence. (break D)

    KEYED ON THE CONTRACT, NOT ON THE EXACT DICT. This asserted equality with a
    three-key literal and went red the day `hole_jobs` was added -- a guard
    whose subject is "every key is always present" should not fail because
    another always-present key arrived. The property is that each named key
    exists and is empty; a new field is not a regression, and a MISSING one is.
    """
    s = tm.skip_summary([_J("a", "pass"), _J("b", "fail")])
    for k, empty in (("count", 0), ("coverage_holes", 0),
                     ("by_reason", {}), ("hole_jobs", [])):
        assert k in s, "%s absent from an empty summary: %s" % (k, s)
        assert s[k] == empty, "%s should be %r on an empty summary: %s" % (k, empty, s)
    return "every documented key is present and empty, whatever else is added"


def t_only_skip_status_counts():
    """`skipped` (never launched) and `interrupted` are NOT skips. (break C)

    They have their own field, `unreached`. Merging them would double-count
    and would relabel a dependency failure as a coverage hole.
    """
    jobs = [_J("a", "skipped"), _J("b", "interrupted"),
            _J("c", "fail"), _J("d", "pass")]
    assert tm.skip_summary(jobs)["count"] == 0
    return "only status=skip is counted"


def t_groups_by_reason():
    jobs = [_J("a", "skip", "corpus absent: external/x"),
            _J("b", "skip", "corpus absent: external/x"),
            _J("c", "skip", "tool absent: fpc is not on PATH")]
    s = tm.skip_summary(jobs)
    assert s["count"] == 3
    assert s["by_reason"]["corpus absent: external/x"] == ["a", "b"]
    assert s["by_reason"]["tool absent: fpc is not on PATH"] == ["c"]
    return "skips group under their own reasons"


def t_coverage_holes_counted_separately():
    """A box lacking a corpus is a hole; a recipe guarding itself may not be.

    This is break B: one hardcoded cause for every skip. The FPC canary and an
    absent corpus are both holes but for different reasons, and a recipe's own
    guard is the recipe's business — the harness does not get to relabel it.
    """
    jobs = [_J("a", "skip", "corpus absent: external/c-testsuite"),
            _J("b", "skip", "tool absent: fpc is not on PATH"),
            _J("c", "skip", "uforth: SKIP no checkout, by design")]
    s = tm.skip_summary(jobs)
    assert s["count"] == 3, s
    assert s["coverage_holes"] == 2, \
        "a recipe's own guard was counted as a coverage hole: %s" % s
    return "holes and self-guards are counted apart"


def t_a_reasonless_skip_says_so_and_is_not_a_hole():
    """"" must not silently become a cause. (break A)

    It reads as "the job did not say", which is a statement about the harness,
    not about the corpus — and it must not inflate the hole count, because
    claiming a coverage hole we cannot substantiate is the same error pointed
    the other way.
    """
    s = tm.skip_summary([_J("a", "skip", "")])
    assert list(s["by_reason"]) == ["(the job did not say)"], s
    assert s["coverage_holes"] == 0
    return "an unexplained skip is labelled, not invented"


def t_names_are_sorted_and_stable():
    s = tm.skip_summary([_J("z", "skip", "r"), _J("a", "skip", "r")])
    assert s["by_reason"]["r"] == ["a", "z"]
    return "job names sort, so the report diffs cleanly"


# --------------------------------------------------------- _self_skipped --

class _Stub(object):
    _SKIP_RE_CACHE = {}


class _LogJob(object):
    def __init__(self, target, logpath):
        self.target = target
        self.logpath = logpath


def _self_skip(target, text):
    stub = _Stub()
    stub._SKIP_RE_CACHE = {}
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
        f.write(text)
        p = f.name
    try:
        return tm.Manager._self_skipped(stub, _LogJob(target, p))
    finally:
        os.unlink(p)


def t_self_skip_returns_the_line_not_a_bool():
    """The reason only the job knows. (break A)"""
    why = _self_skip("test-uforth",
                     "building\ntest-uforth: SKIP no uforth checkout\ndone\n")
    assert why == "test-uforth: SKIP no uforth checkout", repr(why)
    return "the recipe's own SKIP line is the reason"


def t_self_skip_still_reads_as_a_boolean():
    """Callers branch on truthiness; "" must stay falsy."""
    assert not _self_skip("test-x", "test-x: ok\nall good\n")
    assert _self_skip("test-x", "test-x: SKIP why\n")
    return "skip/pass decision is unchanged"


def t_bare_marker_still_beats_empty():
    why = _self_skip("test-x", "test-x: SKIP\n")
    assert why == "test-x: SKIP", repr(why)
    return "a bare marker distinguishes declined from harness-skipped"


def t_corpus_variant_is_matched():
    why = _self_skip("test-lua", "test-lua: corpus SKIP tree absent\n")
    assert why.startswith("test-lua: corpus SKIP"), repr(why)
    return "the `corpus SKIP` spelling still matches"


def t_a_paragraph_is_bounded():
    """This lands in a JSON report committed to git."""
    why = _self_skip("test-x", "test-x: SKIP " + ("y" * 500) + "\n")
    assert len(why) <= 200, len(why)
    return "a chatty recipe cannot bloat the report"


def t_missing_log_is_not_a_skip():
    stub = _Stub()
    stub._SKIP_RE_CACHE = {}
    assert tm.Manager._self_skipped(
        stub, _LogJob("t", "/nonexistent/nope.log")) == ""
    return "an absent log yields no skip and no exception"


# ------------------------------------------------------------ wiring guard --

def t_report_json_carries_skips():
    """The field must reach the published report, not just the console.

    Asserted against the source: the report dict is built deep inside main()
    behind a full run. The whole ticket is that the PUBLISHED artefact was
    silent — a fix that only improves stdout would satisfy every other guard
    here and none of the ticket.
    """
    src = open(os.path.join(HERE, "testmgr.py")).read()
    assert '"skips": skip_summary(jobs),' in src, \
        "the report JSON does not carry a skip summary"
    i, j = src.index('"unreached":'), src.index('"skips":')
    assert abs(src.count("\n", 0, j) - src.count("\n", 0, i)) < 40, \
        "skips drifted away from unreached; they answer the same question"
    return "the report JSON carries skips, beside unreached"


def t_final_count_is_recomputed_after_the_run():
    """The summary must not use the pre-run count. (break C)"""
    src = open(os.path.join(HERE, "testmgr.py")).read()
    i = src.index('npass = sum(1 for j in jobs if j.status == "pass")')
    assert 'nskip = skips["count"]' in src[i:i + 900], \
        "the report summary still uses the pre-run nskip, so a job that " \
        "skipped itself during the run stays invisible"
    return "skip count is recomputed at report time"


# --------------------------------------------------- the PUBLISHED artefact --
# testmgr producing the field is half the fix. The ticket is about what a
# reader of tstate sees days later, and the archive had no skip key at all.

def _tw():
    s = importlib.util.spec_from_file_location(
        "tw", os.path.join(HERE, "twatch.py"))
    m = importlib.util.module_from_spec(s)
    s.loader.exec_module(m)
    return m


def _render(skips, verdict="GREEN"):
    tw = _tw()

    class _C(object):
        def __init__(self, p):
            self.path = p

    rep = {"tier": "full", "wall": "1200", "scale": "1", "verdict": verdict,
           "compiler_sha256": "abc", "jobs": [], "skips": skips}
    with tempfile.TemporaryDirectory() as d:
        rel = tw.write_report_md(_C(d), "h", "a" * 40, "b" * 40, rep,
                                 [], [], [], {"last_by_tier": {}})
        return open(os.path.join(d, rel)).read()


def t_report_header_carries_the_counts():
    body = _render({"count": 50, "coverage_holes": 50, "by_reason": {}})
    assert "skips: 50" in body and "skip_holes: 50" in body, body[:400]
    return "the report header states how much the verdict speaks for"


def t_coverage_banner_fires_on_holes():
    """The 2026-08-26 case: GREEN over a suite that partly did not run."""
    body = _render({"count": 50, "coverage_holes": 50,
                    "by_reason": {"corpus absent: external/x": ["a"]}})
    assert "DID NOT RUN on this box" in body, body[:600]
    assert "speaks for the jobs that ran" in body
    return "a narrowed verdict says so above the fold"


def t_no_banner_when_nothing_was_a_hole():
    """A recipe's own guard is not a coverage hole; don't cry wolf."""
    body = _render({"count": 2, "coverage_holes": 0,
                    "by_reason": {"t: SKIP by design": ["a", "b"]}})
    assert "DID NOT RUN on this box" not in body, body[:600]
    assert "skipped jobs, by reason" in body, "the set is still named"
    return "self-guarded skips are listed but not alarming"


def t_the_skipped_set_is_named_by_reason():
    body = _render({"count": 2, "coverage_holes": 2,
                    "by_reason": {"corpus absent: external/lua":
                                  ["test-lua#00", "test-lua-cross#00"]}})
    assert "corpus absent: external/lua" in body
    assert "test-lua-cross#00" in body
    return "reasons and job names both reach the reader"


def t_a_report_with_no_skip_data_still_renders():
    """Legacy/partial reports must not crash the publisher."""
    body = _render({})
    assert "verdict: GREEN" in body
    assert "DID NOT RUN" not in body
    return "absent skip data degrades quietly"


def t_archive_row_carries_skips():
    src = open(os.path.join(HERE, "twatch.py")).read()
    assert '"skips": (report.get("skips") or {}).get("count")' in src, \
        "the ndjson archive row has no skip count, so no query can find one"
    return "the uncapped archive records the skip count"


def t_a_skipped_advisory_job_renders_as_skip():
    """SKIP must outrank NOTICE in the per-job line.

    "advisory and not pass" is true of a SKIP, so an advisory job that never
    ran printed as NOTICE — the vocabulary of a canary that ran and found
    drift. Anchored on the expression itself, never on the comment above it: an
    assertion that matches prose can be satisfied by prose, which is how an
    earlier guard in this repo fired zero times.
    """
    src = open(os.path.join(HERE, "testmgr.py")).read()
    i = src.index('state = ("SKIP" if j.status == "skip"')
    tail = src[i:i + 240]
    assert 'else "NOTICE" if j.advisory' in tail, \
        "NOTICE is not downstream of SKIP in the state expression"
    return "a skipped advisory job prints SKIP, not NOTICE"


# --------------------------------------------- break E: the classifier and
#                                                the emitters disagreed --

def t_every_emitted_skip_reason_is_classified():
    """Every harness-originated skip reason is a NAMED constant. (break E)

    THE POPULATION IS THE EMITTERS, not the classifier, because the classifier
    is where the answer was already wrong. Measured on
    `20260906T183724Z-6d04b14-seven.md`: 7 skips in three reason groups,
    `skip_holes: 2`. The five uncounted were `host dev dependency absent:` —
    the gtk jobs — because the classifier listed `tool absent:` while the
    emitter said `host tool absent:`, and listed nothing resembling `host dev
    dependency absent:` at all. Both uncounted emitters print, in their own
    prose, "That is coverage this box is not providing". The report published
    the disagreement: "COVERAGE: 2 job(s) DID NOT RUN (of 7 skipped)", three
    lines above a list naming all seven.

    A guard that re-listed the prefixes would be a THIRD copy and could go
    stale the same way, so this one reads testmgr.py's source and requires
    every `skip_reason =` to assign from a `SKIP_*` constant. Adding an emitter
    with a bare literal fails here; adding a constant forces a decision about
    whether it is a hole, because it must appear in SKIP_HOLE_PREFIXES or in
    the named not-a-hole set below.
    """
    src = open(os.path.join(HERE, "testmgr.py"), encoding="utf-8").read()
    lines = src.splitlines()
    # The two assignments that are deliberately not a literal reason, named so
    # an exemption is a decision and not a silence.
    exempt = {'self.skip_reason = ""': "the field's initialiser",
              "job.skip_reason = why": "the recipe's OWN SKIP line, which "
                                       "carries the target name and is the "
                                       "recipe's business, not the harness's"}
    bad = []
    for i, ln in enumerate(lines, 1):
        st = ln.strip()
        if "skip_reason" not in st or "=" not in st:
            continue
        if not st.split("=")[0].strip().endswith("skip_reason"):
            continue
        if st in exempt:
            continue
        rhs = st.split("=", 1)[1].strip().lstrip("(").strip()
        if not rhs:                       # continued on the next line
            rhs = lines[i].strip() if i < len(lines) else ""
        if not rhs.startswith("SKIP_"):
            bad.append("%s:%d  %s" % ("testmgr.py", i, st[:70]))
    assert not bad, ("skip_reason assigned from a bare literal — the emitter "
                     "and the classifier can now disagree silently:\n  "
                     + "\n  ".join(bad))

    # ...and every named constant is classified one way or the other.
    names = [n for n in dir(tm)
             if n.startswith("SKIP_") and n != "SKIP_HOLE_PREFIXES"
             and isinstance(getattr(tm, n), str)]
    not_holes = {"SKIP_INSTRUMENTED_BUILD"}
    unclassified = [n for n in names
                    if getattr(tm, n) not in tm.SKIP_HOLE_PREFIXES
                    and n not in not_holes]
    assert not unclassified, (
        "skip reason constant(s) neither counted as a coverage hole nor named "
        "as deliberately not one: %s" % ", ".join(sorted(unclassified)))
    return "%d emitter constant(s), %d counted as holes" % (
        len(names), len(tm.SKIP_HOLE_PREFIXES))


def t_the_five_reasons_the_report_showed_are_all_holes():
    """The exact seven skips of the 18:37Z report count as seven. (break E)

    A REGRESSION CONTROL WITH REAL DATA, not a synthetic one: these are the
    reason strings that report printed, in its three groups, and the answer it
    gave was 2. If this ever answers 2 again the classifier has drifted back
    off the emitters.
    """
    jobs = [_J("test-zlib#00", "skip", "corpus absent: library_candidates/zlib"),
            _J("test-core#1228", "skip",
               "host capability absent: rdrand — this CPU does not implement "
               "RDRAND/RDSEED (Intel Ivy Bridge 2012 and later), so the job "
               "cannot pass on this box and a red would be permanent")]
    for n in (1819, 1820, 1821, 1822, 1824):
        jobs.append(_J("test-core#%d" % n, "skip",
                       "host dev dependency absent: compiler/gtk.h — this box "
                       "does not have it, so the job cannot pass here and a "
                       "red would be a statement about the box rather than "
                       "about the tree"))
    got = tm.skip_summary(jobs)
    assert got["count"] == 7, got
    assert got["coverage_holes"] == 7, (
        "the 18:37Z report's seven skips counted as %d holes; it published 2"
        % got["coverage_holes"])
    return "7 skips, 7 holes (the report published 2)"


def t_a_recipe_self_skip_is_still_not_a_hole():
    """Widening the prefixes must NOT sweep in a recipe's own SKIP. (break E)

    The negative control for the fix above, and it is the one that keeps this
    from becoming the seven-week "(corpus absent)" bug in the other direction.
    `_self_skipped` returns the whole line, which starts with the target name,
    so it cannot match a prefix by construction — asserted here rather than
    left to construction, because construction is what the classifier was
    relying on when it was wrong.
    """
    got = tm.skip_summary([_J("test-zlib#00", "skip",
                              "test-zlib: SKIP gcc oracle not found")])
    assert got["count"] == 1 and got["coverage_holes"] == 0, got
    return "a recipe's own SKIP line is a skip and not a hole"


TESTS = [t_summary_is_present_when_empty,
         t_a_skipped_advisory_job_renders_as_skip,
         t_report_header_carries_the_counts,
         t_coverage_banner_fires_on_holes,
         t_no_banner_when_nothing_was_a_hole,
         t_the_skipped_set_is_named_by_reason,
         t_a_report_with_no_skip_data_still_renders,
         t_archive_row_carries_skips,
         t_only_skip_status_counts,
         t_groups_by_reason,
         t_coverage_holes_counted_separately,
         t_a_reasonless_skip_says_so_and_is_not_a_hole,
         t_names_are_sorted_and_stable,
         t_self_skip_returns_the_line_not_a_bool,
         t_self_skip_still_reads_as_a_boolean,
         t_bare_marker_still_beats_empty,
         t_corpus_variant_is_matched,
         t_a_paragraph_is_bounded,
         t_missing_log_is_not_a_skip,
         t_report_json_carries_skips,
         t_final_count_is_recomputed_after_the_run,
         t_every_emitted_skip_reason_is_classified,
         t_the_five_reasons_the_report_showed_are_all_holes,
         t_a_recipe_self_skip_is_still_not_a_hole]


def main():
    rc = 0
    print("skip-reason devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("skip-reason OK" if rc == 0 else "skip-reason BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
