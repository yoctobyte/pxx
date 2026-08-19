#!/usr/bin/env python3
"""Guards for fail_detail(): a devtest failure line must never be empty.

The defect this exists to prevent is not a crash -- it is a line of output that
LOOKS like a reason and is not one. So the checks are about what the string
contains, not about whether the call returns.
"""

import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

fails = []


def check(cond, what):
    print("  %s %s" % ("ok  " if cond else "FAIL", what))
    if not cond:
        fails.append(what)


def caught(fn):
    try:
        fn()
    except Exception as e:      # noqa: BLE001 -- catching is the point
        return e
    raise SystemExit("expected %s to raise" % fn)


print("an author's message always wins")
d = fail_detail(caught(lambda: (_ for _ in ()).throw(AssertionError("old epoch not closed"))))
check(d == "old epoch not closed", "a written message passes through untouched")


print("a bare assert reports itself")


def bare():
    value = False
    assert value is True


d = fail_detail(caught(bare))
check(d.strip() != "", "the detail is never empty -- the whole point")
check("no message" in d, "...and it SAYS it had no message, rather than implying one")
check("devtest_report_devtest.py:" in d, "it names the file and line that failed")
check("assert value is True" in d, "and quotes the assert, which cannot drift from itself")


print("the deepest frame, not the runner that caught it")


def outer():
    def inner():
        assert 0
    inner()


d = fail_detail(caught(outer))
check("assert 0" in d, "the reported line is the assert, not the call that reached it")


print("non-assertion exceptions are covered too")
d = fail_detail(caught(lambda: {}["nope"]))
check("nope" in d, "a KeyError carries its own message and keeps it")
check(fail_detail(AssertionError()).strip() != "",
      "an exception with no traceback at all still yields a non-empty detail")


print("end to end: the real case, deliberately broken")
# The measured incident: `assert record_host_epoch(...) is True` printed `FAIL
# <case>: ` and a reader took the NEXT line -- twatch's own success log -- as the
# reason. Break that exact case in a scratch copy and read the harness's output.
src = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "twatch_host_epoch_devtest.py")
with open(src) as f:
    text = f.read()
broken = text.replace('twatch._HW_CACHE["cpu"] = "Not-" + twatch.host_hardware()["cpu"]',
                      'pass  # do not change the hardware, so no epoch opens')
if broken == text:
    check(False, "could not find the line to break -- this guard has gone stale")
else:
    with tempfile.TemporaryDirectory() as td:
        dst = os.path.join(td, "broken_devtest.py")
        with open(dst, "w") as f:
            f.write(broken)
        # The copy lives outside tools/, and its own sys.path.insert points at the
        # temp dir -- so `import twatch` needs PYTHONPATH, or the copy dies on the
        # import and "it did not fail" would mean the wrong thing entirely.
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1",
                   PYTHONPATH=os.path.dirname(os.path.abspath(__file__)))
        out = subprocess.run([sys.executable, dst], env=env, cwd=os.path.dirname(src),
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT
                             ).stdout.decode("utf-8", "replace")
    line = next((ln for ln in out.splitlines()
                 if "FAIL changed-hardware" in ln), "")
    check(line != "", "the broken case does fail (otherwise this proves nothing)")
    detail = line.split(": ", 1)[1].strip() if ": " in line else ""
    check(detail != "", "the FAIL line does not end at the colon -- the measured defect")
    check("is True" in line,
          "the FAIL line carries the assert itself: %s" % line.strip()[:90])
    check("hardware fingerprint changed" not in line,
          "...and not twatch's success log, which is what the reader used to get")

print()
if fails:
    print("FAILED %d check(s):" % len(fails))
    for f_ in fails:
        print("  - " + f_)
    sys.exit(1)
print("all devtest-report guards green")
