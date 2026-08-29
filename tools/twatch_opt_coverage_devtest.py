#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a verdict must say whether the DISJOINT tiers saw the tree.

The nesting chain quick<native<limited<full lets one verdict speak for the
tiers below it. `opt` is outside that chain -- `covered_tiers("opt")` is
`{"opt"}` -- and it runs only as idle watcher work, so a GREEN report says
nothing whatever about any optimisation level above the default `-O`.

Measured 2026-08-28 over `runs-*.ndjson`: 690 of the 2296 shas carrying a
gate-tier verdict had ever been swept by `opt` -- 30% -- and no report named
which 30%. That is the same defect as a skipped job scoring as a pass
(`twatch_skip_anchor_devtest.py`), one level up: an absent signal read as a
negative result. It is what made "no -O3 failures" and "nobody ran -O3"
produce byte-identical evidence, the claim behind
`chore-t-nothing-in-the-matrix-runs-o3-so-no-failures-is-unfalsifiable`.

`last_full` cannot answer the question and is the trap here: it is the last
REPLACING run (`full=True`), and the disjoint tiers run `full=False`, so it
is refreshed by runs that swept no optimisation level at all.

THREE ways to get this wrong, and each guard below says which it catches:

  * break A -- answering from `last_full`, i.e. letting a replacing run at
    another tier vouch for `opt`. Reports coverage that never happened.
  * break B -- answering with `covered_tiers` instead of an exact tier match.
    Coverage is not execution; a `full` run contains no `optdiff` job at all.
  * break C -- counting a torn-down (incomplete) run as coverage. What a run
    did not reach is UNKNOWN, not swept -- the same rule the TIMEOUT banner
    states for the run's own verdict.

Run: tools/twatch_opt_coverage_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)


def _run(sha, tier, date, verdict="GREEN"):
    return {"sha": sha, "tier": tier, "date": date, "verdict": verdict}


# ---------------------------------------------------------------- the helper --

def t_empty_state_has_no_opinion():
    """No state at all -> {}, not a fabricated run. (break A)"""
    assert tw.last_run_at_tier({}, "opt") == {}
    return "empty state yields {}"


def t_reads_last_by_tier():
    st = {"last_by_tier": {"opt": _run("aaaa", "opt", "2026-08-28T09:41:46Z")}}
    assert tw.last_run_at_tier(st, "opt")["sha"] == "aaaa"
    return "last_by_tier is the primary source"


def t_last_full_does_not_answer_for_opt():
    """A replacing `full` run must not be read as an opt sweep. (break A)

    This is the exact confusion the key exists to end: `last_full` is set by
    every complete replacing run, and an opt run never sets it.
    """
    st = {"last_full": _run("bbbb", "full", "2026-08-28T18:29:44Z"),
          "history": [_run("bbbb", "full", "2026-08-28T18:29:44Z")]}
    assert tw.last_run_at_tier(st, "opt") == {}, \
        "a full run answered for opt"
    return "last_full cannot vouch for opt"


def t_exact_tier_not_coverage():
    """`full` nests over `native`, but must not answer AS `native`. (break B)

    Guarding the direction that matters: the helper is about execution, and
    the moment it starts reasoning through covered_tiers it starts reporting
    jobs that were never built.
    """
    # BOTH paths, because they are separate comparisons and a guard that
    # only exercises the key never sees the history scan go wrong. Measured:
    # the first version of this test asserted only the key, and the
    # covered_tiers mutation fired ZERO guards.
    st = {"last_by_tier": {"full": _run("cccc", "full", "2026-08-28T18:29:44Z")}}
    assert tw.last_run_at_tier(st, "native") == {}, \
        "covered_tiers leaked into the last_by_tier lookup"
    assert tw.last_run_at_tier(st, "full")["sha"] == "cccc"

    hist = {"history": [_run("cccc", "full", "2026-08-28T18:29:44Z")]}
    assert tw.last_run_at_tier(hist, "native") == {}, \
        "covered_tiers leaked into the history scan"
    assert tw.last_run_at_tier(hist, "full")["sha"] == "cccc"
    return "exact tier match on both the key and the history scan"


def t_history_fallback_for_legacy_state():
    """State predating the key still answers, from history. (break A)"""
    st = {"history": [_run("dddd", "native", "2026-08-27T01:00:00Z"),
                      _run("eeee", "opt", "2026-08-27T02:00:00Z")]}
    assert tw.last_run_at_tier(st, "opt")["sha"] == "eeee"
    return "legacy state self-heals from history"


def t_history_fallback_takes_the_newest():
    st = {"history": [_run("old1", "opt", "2026-08-20T01:00:00Z"),
                      _run("new1", "opt", "2026-08-27T02:00:00Z")]}
    assert tw.last_run_at_tier(st, "opt")["sha"] == "new1"
    return "history fallback picks the newest match"


def t_key_beats_history():
    """The maintained key wins; history is capped and can be older."""
    st = {"last_by_tier": {"opt": _run("keyy", "opt", "2026-08-28T09:00:00Z")},
          "history": [_run("hist", "opt", "2026-08-20T01:00:00Z")]}
    assert tw.last_run_at_tier(st, "opt")["sha"] == "keyy"
    return "last_by_tier outranks the history scan"


# ---------------------------------------------------------------- the banner --

def _report_body(st, sha, tier="native"):
    """Render a report and return its text, with everything else stubbed out."""
    import tempfile

    class _Clone(object):
        def __init__(self, path):
            self.path = path

    rep = {"tier": tier, "wall": "10", "scale": "1", "verdict": "GREEN",
           "compiler_sha256": "deadbeef", "jobs": []}
    with tempfile.TemporaryDirectory() as d:
        rel = tw.write_report_md(_Clone(d), "devhost", sha, "parent0", rep,
                                 [], [], [], st)
        return open(os.path.join(d, rel)).read()


def t_banner_warns_when_opt_never_ran():
    body = _report_body({"history": []}, "f" * 40)
    assert "never completed an `opt` tier" in body, body[:400]
    return "never-swept host is stated, not implied"


def t_banner_warns_when_opt_is_on_another_sha():
    """The 70% case: opt exists, but not for THIS tree. (break A)"""
    st = {"last_by_tier": {"opt": _run("a" * 40, "opt", "2026-08-27T09:00:00Z")}}
    body = _report_body(st, "b" * 40)
    assert "-O3 IS UNTESTED ON THIS TREE" in body, body[:400]
    assert "aaaaaaaaaaaa" in body, "the report must name the sha opt DID sweep"
    return "opt-on-another-sha reads as untested, and names what was swept"


def t_banner_affirms_when_opt_swept_this_sha():
    """The citable positive an -O2 promotion needs to point at."""
    sha = "c" * 40
    st = {"last_by_tier": {"opt": _run(sha, "opt", "2026-08-28T09:00:00Z")}}
    body = _report_body(st, sha)
    assert "swept on THIS sha" in body, body[:400]
    assert "UNTESTED" not in body
    return "same-sha opt sweep is affirmed"


def t_opt_report_does_not_lecture_itself():
    """An `opt` report obviously covers opt; the banner must stay quiet."""
    body = _report_body({"history": []}, "d" * 40, tier="opt")
    assert "-O3" not in body, body[:400]
    return "no banner on an opt report"


# ------------------------------------------------------------- the state key --

def t_incomplete_run_is_not_coverage():
    """A torn-down run must not land in last_by_tier. (break C)

    Asserted against the SOURCE because the write sits mid-function in the
    publish path; the guard is that the key is written under `not incomplete`
    and not under the replacing branch, which is what makes the disjoint
    tiers record at all.
    """
    src = open(os.path.join(HERE, "twatch.py")).read()
    i = src.index('st["last_by_tier"] = dict(st.get("last_by_tier", {})')
    head = src[:i]
    # the nearest conditional ABOVE the write is the branch it sits in
    cond = [l.strip() for l in head.split("\n") if l.strip().startswith("if ")][-1]
    assert cond == "if not incomplete:", \
        "last_by_tier is written under `%s`; a torn-down run must not count " \
        "as coverage, and the replacing branch would drop opt/slow entirely" % cond
    assert "if full and not incomplete:" in src[i:], \
        "the replacing branch should follow the write, not contain it"
    return "written under `not incomplete`, outside the replacing branch"


# ------------------------------- which run vouches for the cross targets --
# chore-t-the-tier-ladder-ratio-is-stale-by-its-own-criterion records this as
# a prerequisite of its own experiment: the breadth banner read `last_full`,
# which is the last REPLACING run, not the last `full` TIER. They coincide
# only because the shipped default sets mid_tier == deep_tier == full.

def t_breadth_prefers_the_exact_full_tier_over_last_full():
    """The divergent case, which is what enabling mid_tier creates.

    A `limited` run replaces, so it refreshes `last_full` -- and it covers no
    cross target. Reading it would reset the banner's clock on evidence that
    does not support it.
    """
    st = {"last_full": {"tier": "limited", "date": "2026-08-29T12:00:00Z",
                        "sha": "bbbb"},
          "last_by_tier": {"full": {"tier": "full",
                                    "date": "2026-08-27T09:00:00Z",
                                    "sha": "aaaa"}}}
    rec = tw.breadth_full_run(st)
    assert rec.get("sha") == "aaaa", \
        "the banner would vouch for cross targets on a `limited` run: %s" % rec
    assert rec.get("date") == "2026-08-27T09:00:00Z", rec
    return "the OLDER real full tier wins over a newer limited run"


def t_breadth_falls_back_for_state_predating_last_by_tier():
    st = {"last_full": {"tier": "full", "date": "2026-08-29T12:00:00Z",
                        "sha": "cccc"}}
    assert tw.breadth_full_run(st).get("sha") == "cccc"
    return "a pre-last_by_tier full run is still recognised"


def t_the_fallback_can_never_promote_a_non_full_run():
    """The fallback is the risky half, so pin what it refuses to do."""
    st = {"last_full": {"tier": "limited", "date": "2026-08-29T12:00:00Z",
                        "sha": "dddd"}}
    assert tw.breadth_full_run(st) == {}, \
        "the fallback promoted a `limited` run to a cross-target verdict"
    return "the fallback refuses anything that is not a full tier"


def t_no_full_tier_anywhere_returns_empty_not_a_guess():
    """Empty is what makes the caller print the NO-full-tier line."""
    assert tw.breadth_full_run({}) == {}
    assert tw.breadth_full_run({"last_by_tier": {"native": {"tier": "native",
                                                            "date": "x"}}}) == {}
    return "no full tier reports nothing rather than substituting a lesser one"


TESTS = [t_breadth_prefers_the_exact_full_tier_over_last_full,
         t_breadth_falls_back_for_state_predating_last_by_tier,
         t_the_fallback_can_never_promote_a_non_full_run,
         t_no_full_tier_anywhere_returns_empty_not_a_guess,
         t_empty_state_has_no_opinion,
         t_reads_last_by_tier,
         t_last_full_does_not_answer_for_opt,
         t_exact_tier_not_coverage,
         t_history_fallback_for_legacy_state,
         t_history_fallback_takes_the_newest,
         t_key_beats_history,
         t_banner_warns_when_opt_never_ran,
         t_banner_warns_when_opt_is_on_another_sha,
         t_banner_affirms_when_opt_swept_this_sha,
         t_opt_report_does_not_lecture_itself,
         t_incomplete_run_is_not_coverage]


def main():
    rc = 0
    print("opt-coverage devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("opt-coverage OK" if rc == 0 else "opt-coverage BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
