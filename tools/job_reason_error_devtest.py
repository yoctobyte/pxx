#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a red compile job's reason contains the error, not six warnings.

`fpc-bootstrap#src:compiler/compiler.pas` went red on plexus AND seven within
one window on 2026-08-30, and both recorded the same six lines:

    compiler.pas(1546,10) Warning: Variable "CCmdDefCount" ... not ... initialized
    compiler.pas(1557,10) Warning: Variable "CCmdUndefCount" ... not ... initialized
    compiler.pas(2003,54) Warning: Comment level 2 found
    compiler.pas(2194) Fatal: There were 1 errors compiling module, stopping
    Fatal: Compilation aborted
    Error: /usr/bin/ppcx64 returned an error exitcode

Three warnings a PASSING build emits too (960 of them per build), and three
lines saying an error happened without saying which. The reason named an error
and did not contain it -- and the log lives on the watcher's clone, where no
reader of tstate can go.

`job_reason()` keeps the last REASON_LINES lines of the log's last
REASON_TAIL_BYTES. For a compile job that warns in volume the tail IS warnings,
by construction, and the error is out of frame whenever more than six lines
follow it. Not a shape the tail covers badly -- one it cannot cover at all.

THE FIX MUST BE ADDITIVE, and that is what most of this file tests. The
docstring's argument for a tail over a signature list is right: a signature list
goes stale silently and then reports nothing for shapes it has not met. So the
new line is added ONLY when the tail carries no error of its own, and section 3
below pins the untouched cases against an oracle -- a verbatim copy of the
pre-fix logic -- rather than against my memory of them.

TWO GUARDS DO THE DISCRIMINATING and both are worth naming:

  * The FPC fixture's error is SIX LINES from the end of a 90KB log -- inside
    the byte window, out of frame by line count alone. Section 1 asserts both
    halves, because the first cut of this file asserted ">8KB from EOF" and was
    measuring the wrong thing: raising REASON_TAIL_BYTES fixes nothing here.
    A second fixture, whose error IS beyond the byte window, is what makes the
    wider scan earn its keep -- one mechanism per fixture, neither assumed.
  * The tail of the FPC fixture CONTAINS `Error: ... returned an error
    exitcode`. Without _REASON_ERRORLESS_RE, "the tail already shows an error"
    is true and the scan never runs -- the fix would be inert on the exact case
    that motivated it. Section 4 is that distinction alone.

Run: python3 tools/job_reason_error_devtest.py
"""

import os
import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import testmgr as t                                                # noqa: E402

fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-60s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


class Stub:
    def __init__(self, path):
        self.logpath = path


def old_job_reason(path):
    """The pre-fix implementation, verbatim, as the oracle for "unchanged".

    Copied rather than imported on purpose: this is the thing the fix must not
    disturb, so it has to keep working after the original is gone.
    """
    with open(path, "rb") as f:
        try:
            f.seek(-t.REASON_TAIL_BYTES, os.SEEK_END)
        except OSError:
            f.seek(0)
        tail = f.read().decode(errors="replace")
    lines = [ln.rstrip() for ln in tail.splitlines()]
    while lines and (not lines[-1].strip() or t._REASON_NOISE_RE.match(lines[-1])):
        lines.pop()
    lines = [ln for ln in lines[-t.REASON_LINES:] if ln.strip()]
    if not lines:
        return ""
    out = t._REASON_TMP_RE.sub("$TMP", " | ".join(ln.strip() for ln in lines))
    return out[:t.REASON_MAX - 1] + "…" if len(out) > t.REASON_MAX else out


def write(td, name, text):
    p = os.path.join(td, name)
    with open(p, "w") as f:
        f.write(text)
    return p


# --- fixtures -------------------------------------------------------------

FPC_ERROR = ("compiler.pas(2101,17) Error: Identifier not found "
             "\"ThreadSafeModeForTarget\"")

def fpc_log():
    """1000 warnings, one error, then FPC's three content-free summary lines."""
    out = ["Free Pascal Compiler version 3.2.2+dfsg-49 [2026/02/27] for x86_64",
           "Compiling compiler/compiler.pas"]
    for i in range(1000):
        out.append('compiler.pas(%d,10) Warning: Variable "V%d" does not seem '
                   'to be initialized' % (100 + i, i))
    out.append(FPC_ERROR)
    out.append('compiler.pas(1546,10) Warning: Variable "CCmdDefCount" does not '
               'seem to be initialized')
    out.append('compiler.pas(1557,10) Warning: Variable "CCmdUndefCount" does '
               'not seem to be initialized')
    out.append("compiler.pas(2003,54) Warning: Comment level 2 found")
    out.append("compiler.pas(2194) Fatal: There were 1 errors compiling module, "
               "stopping")
    out.append("Fatal: Compilation aborted")
    out.append("Error: /usr/bin/ppcx64 returned an error exitcode")
    return "\n".join(out) + "\n"


QUIET_DIFF = "\n".join(
    ["--- expected", "+++ got"] +
    ["-line %d" % i for i in range(40)] +
    ["+line %d" % i for i in range(40)]) + "\n"

TAIL_HAS_ERROR = "\n".join(
    ["building", "linking"] +
    ["note %d" % i for i in range(500)] +
    ["foo.c:12:3: error: too few arguments to function 'bar'",
     "make: *** [Makefile:9: foo] Error 1"]) + "\n"


def main():
    with tempfile.TemporaryDirectory(
            dir=os.environ.get("TESTMGR_TMP") or os.environ.get("TMPDIR")
            or "/tmp") as td:
        fpc = write(td, "fpc.log", fpc_log())
        quiet = write(td, "quiet.log", QUIET_DIFF)
        tail_err = write(td, "tailerr.log", TAIL_HAS_ERROR)
        short = write(td, "short.log", "boom\nsplat\n")
        empty = write(td, "empty.log", "")

        print("1. the fixture reproduces the real shape, and names the mechanism")
        body = fpc_log()
        off = len(body) - body.index(FPC_ERROR)
        after = body[body.index(FPC_ERROR):].count("\n") - 1
        # The error is NOT beyond the byte window -- it is six lines from the
        # end of a 90KB log. Raising REASON_TAIL_BYTES would therefore change
        # nothing, and a guard that asserted "beyond 8KB" would have been
        # measuring the wrong thing (it was, on the first cut of this file).
        check(off < t.REASON_TAIL_BYTES,
              "the error is INSIDE the byte window...",
              "%d bytes from EOF, window %d" % (off, t.REASON_TAIL_BYTES))
        check(after >= t.REASON_LINES,
              "...and out of frame purely by LINE COUNT, which is the mechanism",
              "%d lines follow it, REASON_LINES=%d" % (after, t.REASON_LINES))
        check(FPC_ERROR not in old_job_reason(fpc),
              "so the OLD implementation cannot see it -- the guard discriminates")
        check("Warning" in old_job_reason(fpc),
              "and reports warnings in its place, exactly as observed")
        # ...and the byte window still has to grow, because nothing bounds how
        # much a build prints after the error that killed it.
        deep = write(td, "deep.log", "\n".join(
            ["cc -c a.c", "a.c:7:1: error: BURIED DEEP"] +
            ["  inlined from 'f' at h.h:%d:%d" % (i, i % 40) for i in range(4000)]
            + ["make: *** [Makefile:4: a.o] Error 1"]) + "\n")
        dbody = open(deep).read()
        check(len(dbody) - dbody.index("BURIED DEEP") > t.REASON_TAIL_BYTES,
              "a second fixture puts one beyond REASON_TAIL_BYTES entirely",
              "%d bytes from EOF" % (len(dbody) - dbody.index("BURIED DEEP")))
        check("BURIED DEEP" in t.job_reason(Stub(deep)),
              "and the wider scan window is what reaches it")
        check("BURIED DEEP" not in old_job_reason(deep),
              "which the old tail could not, at any REASON_LINES")

        print("2. the fix reports the error")
        got = t.job_reason(Stub(fpc))
        check(FPC_ERROR in got, "the Error: line is in the reason", got[:90])
        check(got.startswith(FPC_ERROR),
              "first, because it happened first -- the reason stays in log order")
        check("Fatal: There were 1 errors" in got,
              "and the tail it used to be is still there behind it")
        check(len(got) <= t.REASON_MAX,
              "within REASON_MAX -- tstate is committed to git", "%d" % len(got))

        print("3. and changes NOTHING otherwise (oracle: the pre-fix code)")
        for name, path in (("a diff with no error text", quiet),
                           ("a tail that already names the error", tail_err),
                           ("a log shorter than the tail window", short)):
            check(t.job_reason(Stub(path)) == old_job_reason(path),
                  "byte-identical: %s" % name)
        check(t.job_reason(Stub(empty)) == "",
              "an empty log still reads as 'unknown', not as a reason")
        check(t.job_reason(Stub(None)) == "",
              "and a job with no log at all returns ''")
        check(t.job_reason(Stub(os.path.join(td, "gone.log"))) == "",
              "as does one whose log is missing")

        print("4. THAT something failed is not WHAT failed")
        for line in ("Error: /usr/bin/ppcx64 returned an error exitcode",
                     "compiler.pas(2194) Fatal: There were 1 errors compiling "
                     "module, stopping",
                     "Fatal: Compilation aborted",
                     "make[2]: *** [Makefile:9: foo] Error 1",
                     "Error 1"):
            check(not t.substantive_error(line),
                  "not substantive: %s" % line[:46])
        check(TAIL_HAS_ERROR.count("error:") == 1
              and t.job_reason(Stub(tail_err)).count("error:") == 1,
              "and a real error in the tail is not doubled by the scan")

        print("5. ...but a line that says what went wrong is kept")
        for line in (FPC_ERROR,
                     "foo.c:12:3: error: too few arguments to function 'bar'",
                     "test.pas(9) Fatal: Syntax error, \";\" expected",
                     "Assertion failed: (n > 0), function f, file a.c, line 3.",
                     "Segmentation fault (core dumped)",
                     "ld: undefined reference to `pxx_main'",
                     "panic: runtime error: index out of range"):
            check(t.substantive_error(line), "substantive: %s" % line[:46])

        print("6. one line can never eat the budget")
        huge = write(td, "huge.log", "\n".join(
            ["Error: " + "x" * 5000] + ["note %d" % i for i in range(3000)]) + "\n")
        g = t.job_reason(Stub(huge))
        check(g.startswith("Error: xxx"), "a 5000-char error still leads")
        check(len(g.split(" | ")[0]) <= t.REASON_ERROR_MAX,
              "capped at REASON_ERROR_MAX", "%d" % len(g.split(" | ")[0]))
        check(" | note" in g, "so the tail survives beside it")

        print("7. the LAST error above the tail wins, not the first")
        multi = write(td, "multi.log", "\n".join(
            ["a.c:1:1: error: FIRST"] + ["pad %d" % i for i in range(400)] +
            ["b.c:2:2: error: LAST"] + ["note %d" % i for i in range(200)]) + "\n")
        m = t.job_reason(Stub(multi))
        check("LAST" in m and "FIRST" not in m,
              "nearest to the failure, not earliest in the run", m[:70])

    print("\n  %d guard(s), %d FAIL" % (32, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
