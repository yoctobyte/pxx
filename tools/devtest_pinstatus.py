#!/usr/bin/env python3
"""Devtest: `trackt.py pinstatus` — the pin.log x tstate JOIN.

Gate for deliverable 1 of task-t-pin-fast-track-t-owns-verification, which
asks for this to be "exercised against a real pin.log + tstate/ pair rather
than a synthetic one" — so the first half runs against THIS checkout's actual
data, and only the edge cases (empty log, RED pin) are synthesised, because
they cannot be conjured from real history on demand.

The property under test is not the formatting. It is that the three answers
stay distinguishable:

    GREEN        T judged this sha and liked it
    RED          T judged this sha and did not
    NOT JUDGED   T has not judged this sha at all

Collapsing the third into either of the others is the whole failure mode. A
pin nobody has tested is not a pin that passed, and the fast-pin trade
(recover, don't prevent) only works if the fallback line is trustworthy.

Run: tools/devtest_pinstatus.py   (exit 0 = pass)
"""
import importlib.util
import io
import os
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.argv = ["trackt"]
spec = importlib.util.spec_from_file_location("tk", os.path.join(HERE, "trackt.py"))
tk = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(tk)
except SystemExit:
    pass

fails = []


def check(cond, what, detail=""):
    print("  %-4s %-46s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def run_pinstatus(repo):
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = tk.cmd_pinstatus(repo)
    return rc, buf.getvalue()


def main():
    print("against the REAL pin.log + tstate/ in this checkout")
    pins = tk.read_pin_log(REPO)
    check(len(pins) > 10, "pin.log parses", "%d pins" % len(pins))
    check(all(len(p["git"]) == 40 for p in pins),
          "every row yields a 40-char git sha",
          "two shapes in this file; the git sha is last in both")
    runs = tk.tstate_runs(REPO)
    check(len(runs) > 100, "tstate runs load", "%d judged shas" % len(runs))
    check(any("full" in t for t in runs.values()), "full-tier runs present")

    rc, out = run_pinstatus(REPO)
    check(rc == 0, "pinstatus exits 0")
    check(out.startswith("pin "), "prints the current pin first")
    check("last pin T found fully green" in out,
          "names a fallback target", "the line recovery depends on")

    print("\nthe three answers stay distinct")
    red = next((t for t in runs.values()
                if any(v[0] != "GREEN" for v in t.values())), None)
    green = next((t for t in runs.values() if tk.pin_is_green(t)), None)
    check(red is not None and not tk.pin_is_green(red),
          "a RED tier is not 'fully green'")
    check(green is not None and tk.pin_is_green(green),
          "an all-GREEN sha with a full run is")
    check(not tk.pin_is_green({"native": ("GREEN", "h", "d")}),
          "native-only GREEN is NOT 'fully green'",
          "no full run means no breadth was measured")
    check(not tk.pin_is_green({}), "an unjudged sha is not green",
          "NOT JUDGED must never read as passing")

    print("\nsynthetic edges that real history cannot supply on demand")
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, os.path.dirname(tk.PIN_LOG_REL)))
    os.makedirs(os.path.join(d, "devdocs/progress/tstate"))
    rc, out = run_pinstatus(d)
    check(rc == 1 and "no " in out, "empty/absent pin.log exits 1, says so")

    with open(os.path.join(d, tk.PIN_LOG_REL), "w") as f:
        f.write("2026-01-01T00:00:00Z  pinned v1  %s  (was x)  %s\n"
                % ("a" * 64, "b" * 40))
    rc, out = run_pinstatus(d)
    check("NOT JUDGED" in out, "an unjudged pin says NOT JUDGED",
          "not GREEN, not RED")
    check("NONE in this log" in out,
          "no green pin -> says there is no fallback",
          "silence here would imply a safe target exists")

    print()
    if fails:
        print("FAILED %d check(s): %s" % (len(fails), ", ".join(fails)))
        return 1
    print("pinstatus: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
