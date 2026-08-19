#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a RESOLVED ticket must not suppress the next stub for that job.

`already_filed` scans every bucket so one job never holds two tickets at once.
It did not distinguish WHY a ticket exists. One in an open bucket means the work
is still owed; one in `done/` means a PREVIOUS red was already answered. Keying
suppression on both made a job unticketable forever after its first ticket
resolved — silently, because the filing loop just `continue`d and printed
nothing.

Measured 2026-08-19: 182 resolved `regression-*` slugs, i.e. 182 jobs that could
no longer file. `lib-test#src:test/lib_tls.pas` went NEW-RED at 6070883b46e7 and
no stub appeared, while its own predecessor had closed saying "reopening is by a
fresh NEW-RED stub".

What must hold:

  * nothing filed anywhere            -> the base slug;
  * an OPEN ticket (any open bucket)  -> suppressed, still exactly one at a time;
  * a RESOLVED ticket (done/rejected) -> the next free variant, and it SAYS so;
  * resolved base AND resolved -2     -> -3;
  * resolved base, but -2 is OPEN     -> suppressed (the recurrence is ticketed);
  * zero-byte debris                  -> suppresses nothing, in any bucket;
  * the runaway guard trips, loudly, rather than filing without end;
  * close can FIND what filing opened — live_stub_slug returns the backlog
    variant, not the resolved predecessor.

Pure filesystem fixture: no clone, no daemon, no network.
Run: python3 tools/twatch_refile_stub_devtest.py
"""
import contextlib
import io
import pathlib
import shutil
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import twatch  # noqa: E402

BASE = "regression-lib-test-lib-tls"
FAILURES = []


def check(cond, msg):
    print("  %-4s %s" % ("ok" if cond else "FAIL", msg))
    if not cond:
        FAILURES.append(msg)


def pdir_with(**buckets):
    """A progress dir; `bucket=[slug, ...]` writes a real ticket per slug.

    A slug given as `(slug, "")` is written EMPTY — the zero-byte debris case.
    """
    d = tempfile.mkdtemp(prefix="twatch-refile-")
    for b in twatch.PROGRESS_BUCKETS:
        (pathlib.Path(d) / b).mkdir(parents=True)
    for b, slugs in buckets.items():
        for sl in slugs:
            sl, body = sl if isinstance(sl, tuple) else (sl, "a real ticket\n")
            (pathlib.Path(d) / b / (sl + ".md")).write_text(body)
    return d


def filing(pdir, base=BASE):
    """(chosen slug or None, what it printed)."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        got = twatch.stub_slug_for_filing(pdir, base)
    return got, buf.getvalue()


def main():
    print("nothing filed anywhere")
    d = pdir_with()
    got, out = filing(d)
    check(got == BASE, "files under the base slug (%s)" % got)
    check(out == "", "and says nothing — this is the ordinary case")
    shutil.rmtree(d)

    print("an OPEN ticket already exists")
    for b in twatch.OPEN_BUCKETS:
        d = pdir_with(**{b: [BASE]})
        got, _ = filing(d)
        check(got is None, "%-11s suppresses — one live ticket per job" % (b + "/"))
        shutil.rmtree(d)

    print("the previous ticket is RESOLVED")
    for b in ("done", "rejected"):
        d = pdir_with(**{b: [BASE]})
        got, out = filing(d)
        check(got == BASE + "-2", "%-10s refiles as %s" % (b + "/", got))
        check(BASE in out and "second finding" in out,
              "           and announces it rather than filing quietly")
        shutil.rmtree(d)

    print("resolved twice over")
    d = pdir_with(done=[BASE, BASE + "-2"])
    got, _ = filing(d)
    check(got == BASE + "-3", "walks to the next free variant (%s)" % got)
    shutil.rmtree(d)

    print("resolved base, but the recurrence is already open")
    d = pdir_with(done=[BASE], backlog=[BASE + "-2"])
    got, _ = filing(d)
    check(got is None, "suppressed — the second finding already has its ticket")
    shutil.rmtree(d)

    print("zero-byte debris")
    for b in ("done", "backlog"):
        d = pdir_with(**{b: [(BASE, "")]})
        got, _ = filing(d)
        check(got == BASE, "%-9s empty file suppresses nothing (%s)" % (b + "/", got))
        shutil.rmtree(d)

    print("the runaway guard")
    d = pdir_with(done=[BASE] + ["%s-%d" % (BASE, i)
                                 for i in range(2, twatch.STUB_VARIANT_MAX + 1)])
    got, out = filing(d)
    check(got is None, "stops filing after %d" % twatch.STUB_VARIANT_MAX)
    check("separate times" in out, "and says why, rather than going quiet")
    shutil.rmtree(d)

    print("closing can find what filing opened")
    d = pdir_with(done=[BASE], backlog=[BASE + "-2"])
    check(twatch.live_stub_slug(d, BASE) == BASE + "-2",
          "live_stub_slug returns the backlog variant, not the done/ predecessor")
    shutil.rmtree(d)
    d = pdir_with(done=[BASE])
    check(twatch.live_stub_slug(d, BASE) is None,
          "...and None when nothing is live, so close falls back to the base")
    shutil.rmtree(d)

    if FAILURES:
        print("\n%d check(s) FAILED" % len(FAILURES))
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
