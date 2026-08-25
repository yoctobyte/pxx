#!/usr/bin/env python3
"""An aborted run must cost the work it had LEFT, not the work it had DONE.

Shape 2 of bug-t-the-push-rate-starves-breadth-coverage-entirely. testmgr
already wrote a full report on SIGINT -- verdict INTERRUPTED, every job it had
finished -- and run_gate threw it away by returning before reading it. So an
idle phase offered 299s slices of a 21-minute tier discarded 100% of its work
every time, forever, and never converged. These checks pin the carry-over and
the three ways it could be wrong:

  * carrying results that are not attributable to this binary (the compiler
    rebuilt to different bytes) -- a WRONG verdict, the worst outcome;
  * carrying a job whose ARTIFACTS are gone, because something still to run
    depends on it -- a failure that would read as an ordinary test red;
  * laundering a carried RED into a GREEN verdict, because the failure was
    decided in an earlier process and this run's rc knows nothing about it.

And one that is not a bug but a blind spot: a resume that always discards is
indistinguishable from a resume that works unless the discards are COUNTED.

Run: python3 tools/twatch_resume_devtest.py
"""
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr
import twatch


class FakeClone:
    def __init__(self, path):
        self.path = path
        # the watched branch: verdict-deriving helpers ask the CLONE,
        # never a process default, so a double needs one too
        self.branch = "master"
        os.makedirs(os.path.join(path, ".testmgr"), exist_ok=True)


class FakeJob:
    """Only the fields resume touches. Deliberately not testmgr.Job: that
    constructor parses recipe lines, and none of this is about recipes."""

    def __init__(self, name, sel, deps=(), status="queued"):
        self.name = name
        self.sel = sel
        self.deps = list(deps)
        self.status = status


SHA_A = "aaaaaaaaaaaa1111111111111111111111111111"
SHA_B = "bbbbbbbbbbbb2222222222222222222222222222"
BIN_1 = "1" * 64
BIN_2 = "2" * 64


def decided(sel, status="pass"):
    return {"name": sel, "sel": sel, "status": status}


def main():
    fails = []

    def check(cond, what):
        print(("  ok   " if cond else "  FAIL ") + what)
        if not cond:
            fails.append(what)

    with tempfile.TemporaryDirectory() as tmp:
        part = os.path.join(tmp, "partial.json")

        def write_partial(tier="full", compiler=BIN_1, jobs=None):
            with open(part, "w") as f:
                json.dump({"sha": SHA_A, "tier": tier,
                           "compiler_sha256": compiler,
                           "jobs": jobs if jobs is not None
                           else [decided("test-core#src:a.pas"),
                                 decided("test-core#src:b.pas")]}, f)

        print("a partial is carried only when it is about THIS binary")
        write_partial()
        got, note = testmgr.load_resume(part, "full", BIN_1)
        check(len(got) == 2, "matching tier + compiler sha256 carries the jobs")
        check("accepted" in note, "and says so: %r" % note)

        got, note = testmgr.load_resume(part, "full", BIN_2)
        check(got == [], "a compiler rebuilt to different bytes carries nothing")
        check("DISCARDED" in note, "and the note names it a discard: %r" % note)

        got, note = testmgr.load_resume(part, "native", BIN_1)
        check(got == [], "a partial from another TIER carries nothing")
        check("DISCARDED" in note, "tier mismatch is a discard: %r" % note)

        write_partial(compiler=None)
        got, note = testmgr.load_resume(part, "full", BIN_1)
        check(got == [] and "DISCARDED" in note,
              "a partial with no compiler sha256 is refused, not trusted")

        got, note = testmgr.load_resume(os.path.join(tmp, "nope.json"),
                                        "full", BIN_1)
        check(got == [], "no partial at all carries nothing")
        check("DISCARDED" not in note,
              "...and is NOT reported as a discard — the first run of a tier "
              "is the normal case, not a degradation")

        with open(part, "w") as f:
            f.write("{not json")
        got, note = testmgr.load_resume(part, "full", BIN_1)
        check(got == [] and "DISCARDED" in note,
              "an unreadable partial is discarded, not raised")

        print("...and only jobs that were actually DECIDED")
        write_partial(jobs=[decided("t#src:a.pas"),
                            {"name": "t#src:c.pas", "sel": "t#src:c.pas",
                             "status": "queued"},
                            {"name": "t#src:d.pas", "sel": "t#src:d.pas",
                             "status": "skipped"}])
        got, _ = testmgr.load_resume(part, "full", BIN_1)
        check([g["sel"] for g in got] == ["t#src:a.pas"],
              "queued/skipped jobs are not results and are not carried")

        print("a job something still to run DEPENDS on is re-run, never carried")
        a = FakeJob("t#01", "t#src:a.pas")
        b = FakeJob("t#02", "t#src:b.pas", deps=[a])
        c = FakeJob("t#03", "t#src:c.pas")
        used = testmgr.apply_resume([a, b, c],
                                    [decided("t#src:a.pas"),
                                     decided("t#src:c.pas")])
        check([u["sel"] for u in used] == ["t#src:c.pas"],
              "the dep of an unfinished job is not carried")
        check(a.status == "queued", "...it stays runnable")
        check(c.status == "carried", "...while an independent job is carried")

        print("...transitively, not just one level")
        a = FakeJob("t#01", "t#src:a.pas")
        b = FakeJob("t#02", "t#src:b.pas", deps=[a])
        c = FakeJob("t#03", "t#src:c.pas", deps=[b])
        used = testmgr.apply_resume([a, b, c], [decided("t#src:a.pas"),
                                                decided("t#src:b.pas")])
        check(used == [] and a.status == "queued" and b.status == "queued",
              "a dep-of-a-dep of an unfinished job is re-run too")

        print("a carried entry for a job that no longer exists is dropped")
        a = FakeJob("t#01", "t#src:a.pas")
        used = testmgr.apply_resume([a], [decided("t#src:a.pas"),
                                          decided("t#src:deleted.pas")])
        check([u["sel"] for u in used] == ["t#src:a.pas"],
              "a renamed or deleted test cannot resurrect a stale verdict")

        print("a carried RED is still a RED")
        check(testmgr.carried_red([decided("x", "fail")]),
              "a carried fail keeps the tier red")
        check(testmgr.carried_red([decided("x", "timeout")]),
              "so does a carried timeout")
        check(not testmgr.carried_red([decided("x"), decided("y", "skip")]),
              "...and passes/skips do not manufacture one")

        print("an aborted run must not PUBLISH as a completed one")
        ran = [FakeJob("t#%02d" % i, "s%d" % i, status="pass") for i in range(3)]
        never = [FakeJob("t#%02d" % i, "s%d" % i, status="skipped")
                 for i in range(3, 10)]
        d, t, pct = testmgr.live_progress(ran + never)
        check((d, t) == (3, 10),
              "only jobs that actually finished count as done (got %d/%d)" % (d, t))
        check(pct == 30.0, "...and the percentage follows them, not the teardown")
        d, t, pct = testmgr.live_progress(ran)
        check((d, t, pct) == (3, 3, 100.0),
              "a run that really finished still reports 100%")
        d, t, pct = testmgr.live_progress([])
        check((d, t, pct) == (0, 0, 100.0),
              "an empty job set does not divide by zero")

    print("the twatch side: a partial belongs to ONE (sha, tier)")
    with tempfile.TemporaryDirectory() as tmp:
        clone = FakeClone(tmp)
        rep = {"compiler_sha256": BIN_1,
               "jobs": [decided("t#src:a.pas"), decided("t#src:b.pas")]}
        check(twatch.save_partial(clone, (SHA_A, "full"), rep) == 2,
              "an aborted run's decided jobs are kept")
        check(twatch.resume_arg(clone, (SHA_A, "full")) is not None,
              "the next slice of the same work is offered them")
        check(twatch.resume_arg(clone, (SHA_A, "native")) is None,
              "a different TIER is not")
        check(twatch.resume_arg(clone, (SHA_B, "full")) is None,
              "and neither is a different SHA")

        # THE BUG THIS FILE NOW GUARDS. Under the single slot, the two lines
        # above did not merely decline the partial -- they DELETED it, so the
        # fast native verdict that ends an idle slice destroyed the pin-verify
        # work that had just been preempted. Measured over the feature's entire
        # life: 9 saved, 1420 jobs, 0 carried. The read must be READ-ONLY.
        check(twatch.resume_arg(clone, (SHA_A, "full")) is not None,
              "A RUN OF DIFFERENT WORK DOES NOT EVICT IT — it is still there")

        check(twatch.save_partial(clone, (SHA_B, "quick"), rep) == 2,
              "a second, unrelated partial can be saved at the same time")
        check(twatch.resume_arg(clone, (SHA_A, "full")) is not None
              and twatch.resume_arg(clone, (SHA_B, "quick")) is not None,
              "...and BOTH are readable — the store is keyed, not a slot")

        twatch.drop_partial(clone, (SHA_B, "quick"))
        check(twatch.resume_arg(clone, (SHA_B, "quick")) is None,
              "a run that ENDED drops its own partial")
        check(twatch.resume_arg(clone, (SHA_A, "full")) is not None,
              "...and only its own")

        twatch.drop_partial(clone, (SHA_A, "full"))
        check(twatch.save_partial(clone, (SHA_A, "full"), {"jobs": []}) == 0,
              "an abort that decided nothing writes no partial")
        check(twatch.resume_arg(clone, (SHA_A, "full")) is None,
              "...so the next slice is offered nothing rather than an empty set")
        check(twatch.resume_arg(clone, None) is None,
              "a run that opted out of resuming is never offered one")

        # The name is a convenience; the PAYLOAD is the authority. A truncated
        # or hand-edited file whose contents disagree with its filename is
        # declined rather than resumed against the wrong work.
        bad = twatch.partial_path(clone, (SHA_A, "full"))
        os.makedirs(os.path.dirname(bad), exist_ok=True)
        with open(bad, "w") as f:
            json.dump({"sha": SHA_B, "tier": "full", "jobs": []}, f)
        check(twatch.resume_arg(clone, (SHA_A, "full")) is None,
              "a partial whose contents disagree with its filename is declined")
        os.unlink(bad)

    print("the store is BOUNDED — and says what it dropped")
    with tempfile.TemporaryDirectory() as tmp:
        clone = FakeClone(tmp)
        rep = {"compiler_sha256": BIN_1, "jobs": [decided("t#src:a.pas")]}
        # Distinct in the FIRST 12 chars, because that is the slice the
        # filename is built from. "%040d" would have made every key collide on
        # a run of zeros and turned the whole cap test vacuous.
        keys = [(("%d%s" % (i + 1, "a" * 40))[:40], "full")
                for i in range(twatch.PARTIAL_CAP + 2)]
        for n, k in enumerate(keys):
            twatch.save_partial(clone, k, rep)
            # mtime, not write order, is what the GC sorts on, and a same-second
            # filesystem would otherwise make this test a coin flip.
            os.utime(twatch.partial_path(clone, k), (n * 100.0, n * 100.0))
        live = [k for k in keys if twatch.resume_arg(clone, k)]
        check(len(live) <= twatch.PARTIAL_CAP,
              "the store never exceeds PARTIAL_CAP=%d (got %d)"
              % (twatch.PARTIAL_CAP, len(live)))
        check(keys[-1] in live and keys[0] not in live,
              "the NEWEST survive and the oldest are evicted, not the reverse")
        with open(os.path.join(tmp, twatch.RESUME_STATS_REL)) as f:
            stats = json.load(f)
        # An aged-out partial is lost work exactly like an evicted one was, so
        # it stays on the same counter. Dropping it silently would hide a
        # regression behind a healthy-looking saved count.
        check(int(stats.get("superseded") or 0) >= 1,
              "an aged-out partial is still counted as lost work (got %r)"
              % stats.get("superseded"))

    print("...and every outcome is COUNTED, including the do-nothing ones")
    with tempfile.TemporaryDirectory() as tmp:
        clone = FakeClone(tmp)
        st = twatch.bump_resume_stats(clone, discarded=1)
        check(st.get("discarded") == 1, "a testmgr-side discard is counted")
        st = twatch.bump_resume_stats(clone, discarded=1)
        check(st.get("discarded") == 2, "counters accumulate across runs")
        line = twatch.resume_health(st)
        check("discarded" in line and "2" in line,
              "the health line reports RATES, not events: %r" % line)

        print("an abort that left no report is counted, not silently ignored")
        twatch.keep_partial(clone, (SHA_A, "full"),
                            os.path.join(tmp, "no-such-report.json"), "full")
        with open(os.path.join(tmp, twatch.RESUME_STATS_REL)) as f:
            stats = json.load(f)
        check(stats.get("no_report_on_abort") == 1,
              "a SIGKILL after the grace shows up as a number")

    print("\n%d check(s) failed" % len(fails) if fails else "\nall checks pass")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
