#!/usr/bin/env python3
"""Devtest for the signature-scoped retry
(bug-t-etxtbsy-race-reds-single-shot-selfhost-jobs).

`selfhost` is single-shot on purpose: a flake there is a real nondeterminism bug
to reseed, not to paper over. But ETXTBSY is not that — the kernel refuses to
exec a file some process still holds open for writing, which says nothing about
the artifact, and it red a GATED job twice on 2026-08-02 after the compile had
already reported `ok:`.

So the retry must key on the SIGNATURE, not the class, and it must not become a
blanket selfhost retry. Both halves are asserted here, plus the property that
makes the whole thing safe: a real failure carries no signature and stays
single-shot.

Temp files only — no compiler, no repo state, no jobs actually run.
"""
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import testmgr  # noqa: E402

fails = []


def check(name, cond, got=""):
    print(("  ok   " if cond else "  FAIL ") + name +
          (("  got: %s" % got) if not cond and got else ""))
    if not cond:
        fails.append(name)


class FakeJob:
    """Only what _retriable_signature touches."""
    def __init__(self, log, cls="selfhost", attempts=1, advisory=False):
        self.logpath = str(log) if log else None
        self.cls = cls
        self.attempts = attempts
        self.advisory = advisory


def mgr():
    return testmgr.Manager.__new__(testmgr.Manager)   # no __init__: pure method


def logfile(text, name="j.log"):
    d = pathlib.Path(tempfile.mkdtemp(prefix="retrysig-"))
    p = d / name
    p.write_bytes(text.encode())
    return p


ETXTBSY_LOG = """ok: /tmp/scratch/pascal26-self  [code=6048122B  data=181032B  procs=2379]
ok: /tmp/scratch/self-hello26  [code=39880B]
sh: 99: /tmp/scratch/pascal26-next: Text file busy
"""
REAL_FAIL_LOG = """ok: /tmp/scratch/pascal26-self  [code=6048122B]
ok: /tmp/scratch/pascal26-next [code=6048130B]
/tmp/scratch/pascal26-self /tmp/scratch/pascal26-next differ: byte 4096, line 1
"""


def main():
    m = mgr()

    check("ETXTBSY in a SELFHOST log is retriable despite single-shot",
          m._retriable_signature(FakeJob(logfile(ETXTBSY_LOG))) == "Text file busy")

    check("a real fixedpoint MISMATCH is not retriable",
          m._retriable_signature(FakeJob(logfile(REAL_FAIL_LOG))) is None)

    check("the class rule is untouched: selfhost is still not class-retriable",
          m._retriable(FakeJob(logfile(REAL_FAIL_LOG))) is False)
    check("...and a retry class still is",
          m._retriable(FakeJob(logfile(REAL_FAIL_LOG), cls="corpus")) is True)

    check("attempts are still bounded",
          m._retriable_signature(
              FakeJob(logfile(ETXTBSY_LOG),
                      attempts=testmgr.RUN_RETRY_TRIES)) is None)

    check("advisory jobs are not retried (they gate nothing)",
          m._retriable_signature(
              FakeJob(logfile(ETXTBSY_LOG), advisory=True)) is None)

    check("a missing log is not a crash",
          m._retriable_signature(FakeJob(None)) is None)
    check("an unreadable log path is not a crash",
          m._retriable_signature(FakeJob("/nonexistent/nope.log")) is None)

    # the signature must be found even when the log is much larger than the
    # tail window — the failure is always at the END, which is what we scan
    big = logfile("filler line\n" * 20000 + ETXTBSY_LOG, "big.log")
    check("found in a log far larger than the tail window",
          m._retriable_signature(FakeJob(big)) == "Text file busy",
          "%d bytes" % big.stat().st_size)
    # ...but a signature buried only in the HEAD of a huge log is not claimed,
    # which is correct: that is an old line, not this attempt's failure
    stale = logfile(ETXTBSY_LOG + "filler line\n" * 20000, "stale.log")
    check("a signature only in the distant head is ignored",
          m._retriable_signature(FakeJob(stale)) is None)

    check("the bare ETXTBSY spelling also matches",
          m._retriable_signature(
              FakeJob(logfile("exec failed: ETXTBSY\n"))) == "ETXTBSY")

    print()
    print("FAILED: " + ", ".join(fails) if fails else "all retry-signature cases pass")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
