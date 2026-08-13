#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: one transient error must not cascade into hours of lost coverage.

Reconstructed from the 2026-08-12 plexus incident, which cost 16 hours and
discarded a GREEN 2293/2293 full-tier run. The chain, from the log:

  1. `twatch: testing e690d5b02eb3 (full)` — testmgr starts as pid 699491.
  2. `twatch: cycle failed (1/10): git fetch ... exit 128` — a transient fetch
     error raises inside the cycle. NOTHING kills the child; it runs on, holding
     the repo lock.
  3. The retried cycle starts a second full run, which hits
     `testmgr: a run is ALREADY LIVE (pid 699491)` and exits rc=2.
  4. twatch reads rc=2 as "this box cannot measure" and RESEEDS
     compiler/pascal26 from the pinned stable — underneath the orphan, which
     duly logs `compiler/pascal26 changed during this run`.
  5. mark_infra() records the non-event with a bare save_state(), wedging the
     daemon (covered separately by devtest_wedge_on_own_writes.py).
  6. The orphan finishes GREEN 2293/2293. Nobody is listening.

Two independent defects, two invariants:

  * **A cycle that throws must take its gate child with it.** Leaving it alive
    manufactures the lock collision that starts everything else.
  * **rc=2 is contention, not a fault.** A poisoned seed wants a reseed; a busy
    repo wants patience. Reseeding on contention is actively destructive,
    because it rewrites the compiler under the run that legitimately holds the
    lock. Contention must publish no verdict, record no infra event, and above
    all not touch the binary.

Run: tools/devtest_gate_contention.py   (exit 0 = pass)
"""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE,
                                                                "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

# A testmgr that refuses to start exactly the way the real one does.
LOCKED_TESTMGR = """import sys
print("testmgr: a run is ALREADY LIVE (pid 699491, tier full, started 10m12s ago)")
sys.exit(2)
"""


def build(root):
    """A clone whose testmgr always reports the lock, and whose
    `seed-from-stable` leaves a trace if it is ever (wrongly) invoked."""
    clone = os.path.join(root, "clone")
    os.makedirs(os.path.join(clone, "tools"))
    os.makedirs(os.path.join(clone, "compiler"))
    with open(os.path.join(clone, "tools", "testmgr.py"), "w") as f:
        f.write(LOCKED_TESTMGR)
    with open(os.path.join(clone, "Makefile"), "w") as f:
        f.write("seed-from-stable:\n\t@touch %s\n"
                % os.path.join(root, "RESEED-HAPPENED"))
    with open(os.path.join(clone, "compiler", "pascal26"), "w") as f:
        f.write("the binary the lock holder is using")
    c = tw.Clone.__new__(tw.Clone)
    c.path, c.branch, c.remote = clone, "master", None
    return c


def t_contention_is_not_a_fault(root):
    """rc=2 -> 'busy', no verdict, no reseed, compiler untouched."""
    c = build(root)
    comp = os.path.join(c.path, "compiler", "pascal26")
    report, rc = tw.run_gate(c, "full")
    assert rc == "busy", "expected 'busy', got %r" % (rc,)
    assert report is None, report
    assert not os.path.exists(os.path.join(root, "RESEED-HAPPENED")), \
        "reseeded on contention — this rewrites the compiler under the lock holder"
    assert os.path.exists(comp), "compiler was unlinked under the lock holder"
    with open(comp) as f:
        assert "lock holder" in f.read(), "compiler content was replaced"
    return "classified busy; no reseed; binary untouched"


def t_orphan_gate_is_torn_down(_root):
    """A cycle that throws must not leave its gate child holding the lock."""
    p = subprocess.Popen(["sleep", "300"], start_new_session=True)
    tw._GATE_PROC = p
    try:
        assert p.poll() is None, "setup: child should be alive"
        assert tw._kill_orphan_gate() is True
        p.wait(timeout=40)
        assert p.poll() is not None, "child survived the teardown"
        assert tw._GATE_PROC is None, "registry not cleared"
    finally:
        if p.poll() is None:
            p.kill()
    return "live child killed, registry cleared"


def t_no_spurious_kill(_root):
    """No child, or an already-reaped one, must be a silent no-op."""
    tw._GATE_PROC = None
    assert tw._kill_orphan_gate() is False
    done = subprocess.Popen(["true"])
    done.wait()
    tw._GATE_PROC = done
    assert tw._kill_orphan_gate() is False
    assert tw._GATE_PROC is None
    return "no-op for absent and already-reaped children"


def main():
    rc = 0
    for fn in (t_contention_is_not_a_fault, t_orphan_gate_is_torn_down,
               t_no_spurious_kill):
        root = tempfile.mkdtemp(prefix="devtest-contention-")
        try:
            print("  ok   %s — %s" % (fn.__name__, fn(root)))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s" % (fn.__name__, type(e).__name__, e))
        finally:
            shutil.rmtree(root, ignore_errors=True)
    print("gate contention handling OK" if rc == 0
          else "gate contention handling BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
