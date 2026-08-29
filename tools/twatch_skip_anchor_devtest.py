#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a SKIP is not a last-good, and must not become a red either.

`PASSLIKE = ("pass", "skip")`, so a job whose corpus is absent SKIPs and the
run that contained it looks like a clean anchor. `last_covering_sha()` asks
which earlier run's tier CONTAINED the job -- tier coverage, not execution --
so the coverage answer is confidently wrong exactly when the job never ran.

Measured 2026-08-27, filed by frankB (Track B) out of the synapse triage:
`external/synapse` was absent on plexus, three synapse jobs skipped for their
whole life, and the first real execution after the corpus landed was published
as a regression over NINE commits, five touching `lib/` or the pin, all nine
innocent. frankB proved it by rebuilding the declared last-good's own tree
under the pin actually in force there and watching it fail identically.

    A first-ever run is not a regression, and a sha where a job did not
    execute is not a last-good.

THIS FILE BREAKS IT TWICE ON PURPOSE, because the obvious fix has an equal and
opposite failure mode and one test would pass for both:

  * break A -- a skip counted GOOD. The original bug: a fabricated range full
    of innocent commits, and a bisect over it does not fail, it terminates and
    names one.
  * break B -- a skip counted RED. The mirror image the fix must not cause:
    every job whose corpus is legitimately absent on a box turns into a false
    alarm, the run verdict goes red, and open regressions stop closing.

Each case below says which break it catches. A guard that cannot say is the
check that cannot fail, and this whole ticket is one of those.

Run: tools/twatch_skip_anchor_devtest.py   (exit 0 = pass)
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

JOB = "lib-test#src:test/lib_synapse.pas"


def rep(*pairs, **kw):
    return {"tier": kw.get("tier", "full"), "verdict": kw.get("verdict", "RED"),
            "jobs": [{"sel": n, "name": n, "status": s} for n, s in pairs]}


# ---------------------------------------------------- break A: skip as GOOD --

def t_a_skipped_job_is_not_an_anchor():
    """BREAK A. The bug itself, at the smallest scale it exists."""
    st = {"jobs": {JOB: "skip"}, "job_last_pass": {}}
    sha, why = tw.job_anchor(st, JOB)
    assert sha is None, "a job whose last status was SKIP must not anchor: %r" % sha
    assert "SKIP" in why, "and must say why, for the ticket that reads it: %r" % why
    return "skip -> no anchor, with a reason"


def t_a_passing_job_still_anchors():
    """BREAK B's half of the same call. The fix must not blank real anchors."""
    st = {"jobs": {JOB: "pass"}, "job_last_pass": {JOB: "a" * 40}}
    sha, why = tw.job_anchor(st, JOB)
    assert sha == "a" * 40, "a recorded pass must anchor: %r" % sha
    assert why == "", "and must not carry a complaint: %r" % why
    return "pass -> anchored at the sha it passed on"


def t_the_anchor_is_the_last_PASS_not_the_last_RUN():
    """The generalisation the ticket's suggested fix would have missed.

    pass at A, skip at B, fail at C. Anchoring on "previous status" alone gives
    an empty range; anchoring on the last RUN gives B, which the job never
    passed at. Only A is true, and the range A..C is WIDER than the naive one --
    the direction that keeps the culprit inside it.
    """
    st = {"jobs": {JOB: "skip"}, "job_last_pass": {JOB: "A" * 40}}
    sha, why = tw.job_anchor(st, JOB)
    assert sha == "A" * 40, (
        "a job that passed at A and skipped at B must anchor at A, not at B "
        "and not nowhere: %r" % sha)
    assert why == "", "an anchored job carries no complaint: %r" % why
    return "last PASS wins over last RUN"


def t_an_unknown_job_gives_no_opinion():
    """MIGRATION. State written before job_last_pass existed must keep the old
    fallback, not have every range blanked for a cycle."""
    st = {"jobs": {JOB: "pass"}}                 # no job_last_pass key at all
    sha, why = tw.job_anchor(st, JOB)
    assert sha is None and why == "", (
        "legacy state must produce NO OPINION (None, '') so the caller keeps "
        "its old fallback, not a refusal: %r" % ((sha, why),))
    return "legacy state -> no opinion, old fallback preserved"


def t_the_three_returns_are_distinguishable():
    """The distinction the migration rests on: 'never passed' and 'I don't
    know' must not collapse into one value."""
    known_bad = tw.job_anchor({"jobs": {JOB: "skip"}, "job_last_pass": {}}, JOB)
    unknown = tw.job_anchor({"jobs": {}}, JOB)
    good = tw.job_anchor({"job_last_pass": {JOB: "c" * 40}}, JOB)
    assert known_bad[0] is None and known_bad[1], "known-never-passed carries a reason"
    assert unknown[0] is None and not unknown[1], "unknown carries none"
    assert good[0] and not good[1], "anchored carries a sha"
    assert known_bad != unknown, "the two Nones must be distinguishable"
    return "three states, three distinct returns"


# ----------------------------------------------------- break B: skip as RED --

def t_skip_is_still_PASSLIKE():
    """BREAK B, at the root. Moving `skip` out of PASSLIKE would fix the anchor
    by breaking the verdict: a run whose corpus is absent must still be able to
    come back GREEN."""
    assert "skip" in tw.PASSLIKE, (
        "skip must remain PASSLIKE — the anchor fix must SPLIT the two "
        "readings, not reclassify the status")
    assert "pass" in tw.PASSLIKE
    return "skip stays PASSLIKE for the run verdict"


def t_a_skip_does_not_open_a_regression():
    """BREAK B. A job that skips is not a new red."""
    _now, new_red, _f, _s, _fs = tw.diff_jobs({JOB: "pass"}, rep((JOB, "skip")))
    assert JOB not in new_red, "a pass -> skip transition must not be a NEW-RED"
    return "pass -> skip opens nothing"


def t_a_skip_still_closes_an_open_regression():
    """BREAK B. A box that legitimately cannot run a job must not hold a
    regression open forever — the deliberate trade reg_open documents."""
    open_now = tw.reg_open({"job": JOB}, {JOB: "skip"})
    assert not open_now, "red -> skip must still close: a box that cannot run "\
                         "a job must not pin a regression open"
    assert tw.reg_open({"job": JOB}, {JOB: "fail"}), "a real fail keeps it open"
    return "red -> skip still closes"


def t_a_skip_to_fail_is_still_reported_red():
    """The half that must NOT change, and the one a careless fix silently
    loses. The job DID fail. Only the attribution is impossible."""
    _now, new_red, _f, _s, _fs = tw.diff_jobs({JOB: "skip"}, rep((JOB, "fail")))
    assert JOB in new_red, (
        "a job failing its first real execution must still be reported red — "
        "declining to name a commit is not declining to report")
    return "skip -> fail is still a red, only unanchorable"


# ------------------------------------------------------------ the map itself --

def t_only_a_literal_pass_advances_the_map():
    """`skip` must never write job_last_pass, or the bug returns through the
    back door one run later."""
    src = open(os.path.join(HERE, "twatch.py")).read()
    i = src.index('st["job_last_pass"] = dict(')
    # Two lines, not "to the next blank line": the statement is followed
    # immediately by st["history"], so a loose slice dumps 3KB into the failure
    # message. A guard whose output cannot be read is most of a guard that
    # cannot be acted on.
    stmt = "".join(src[i:].splitlines(True)[:2])
    assert 'v == "pass"' in stmt, (
        "the map must advance on a LITERAL pass; anything PASSLIKE-shaped here "
        "re-admits skip as an anchor: %s" % stmt.strip())
    assert "PASSLIKE" not in stmt, (
        "PASSLIKE here would be the original bug, one indirection deeper: %s"
        % stmt.strip())
    return "only a literal pass advances job_last_pass"


def t_range_for_acts_on_the_reason_and_acts_FIRST():
    """The middle link. job_anchor can refuse all it likes; if range_for asks
    the coverage path first, or ignores the refusal, nothing changes.

    Ordering is half of it. Every line below the execution check reasons about
    tier COVERAGE, and the coverage answer is confidently wrong precisely when
    the job never ran — so consulting it first would restore the bug with the
    fix still present in the file, which is the version hardest to notice.
    """
    src = open(os.path.join(HERE, "twatch.py")).read()
    body = src[src.index("    def range_for(name):"):]
    body = body[:body.index("\n\n")]
    assert "job_anchor(st, name)" in body, "range_for must consult job_anchor"
    assert 'return [], ""' in body, (
        "range_for must return an EMPTY range when the job is known never to "
        "have passed — refusing to name a commit is the whole fix")
    # The CALL, not the bare name. The block comment above it mentions
    # job_anchor(), so `body.index("job_anchor")` finds the comment and the
    # ordering assertion passes no matter where the call actually sits. Caught
    # by mutation: moving parent_ran_job above the call fired ZERO guards --
    # the worst of the four breaks, because the fix is still visibly in the
    # file and only unreachable. A guard defeated by a comment is one this
    # ticket family has already paid for twice.
    call = body.index("aname, why = job_anchor(st, name)")
    assert call < body.index("last_covering_sha"), (
        "the execution check must come BEFORE the tier-coverage fallback, or "
        "the coverage answer wins exactly where it is wrong")
    assert call < body.index("parent_ran_job"), (
        "...and before parent_ran_job, which is the same coverage reasoning "
        "wearing a different name — it was the actual path the synapse range "
        "took")
    return "range_for consults job_anchor first and honours a refusal"


def t_the_map_is_pruned_with_its_siblings():
    """A renamed job must not leave a permanent stale anchor behind, for the
    same reason job_tier is pruned: a stale entry is a permanent wrong answer."""
    src = open(os.path.join(HERE, "twatch.py")).read()
    prune = src[src.index("dead = orphan_keys("):]
    prune = prune[:prune.index("update_job_reasons")]
    assert 'st["job_last_pass"]' in prune, (
        "job_last_pass must be pruned beside job_tier and jobs")
    return "the map is pruned with job_tier and jobs"


def t_the_ledger_publishes_the_flag():
    """Readers (tickets, --status, repair_regressions) must be able to SEE that
    a range was withheld, or the fix is invisible where it matters."""
    src = open(os.path.join(HERE, "twatch.py")).read()
    assert '"never_passed": never_passed,' in src, (
        "the ledger entry must carry never_passed beside first_seen")
    return "never_passed is published on the ledger entry"


def main():
    rc = 0
    for fn in (t_a_skipped_job_is_not_an_anchor,
               t_a_passing_job_still_anchors,
               t_the_anchor_is_the_last_PASS_not_the_last_RUN,
               t_an_unknown_job_gives_no_opinion,
               t_the_three_returns_are_distinguishable,
               t_skip_is_still_PASSLIKE,
               t_a_skip_does_not_open_a_regression,
               t_a_skip_still_closes_an_open_regression,
               t_a_skip_to_fail_is_still_reported_red,
               t_only_a_literal_pass_advances_the_map,
               t_range_for_acts_on_the_reason_and_acts_FIRST,
               t_the_map_is_pruned_with_its_siblings,
               t_the_ledger_publishes_the_flag):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("skip-anchor OK" if rc == 0 else "skip-anchor BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
