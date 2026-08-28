#!/usr/bin/env python3
"""How a Track T devtest renders a failure.

One function, because one line of output was costing a reader a whole pass.

A bare `assert f(x) is True` raises an AssertionError whose str() is the empty
string. Every devtest runner here prints `FAIL <case>: {e}`, so an empty message
produces a line that ENDS at the colon -- and the next line of output, usually a
success-path log from the code under test, is what a reader takes as the reason.
Measured cost: a cross-session relay on 2026-08-19 quoted twatch's own
"hardware fingerprint changed" log as the failure detail, because the harness
handed them nothing else to quote, and the receiving agent spent a pass treating
two fingerprints as the finding.

So a failure with no message must say that it has no message, and then say the
one thing that is always available and cannot drift: the source line that
failed. A hand-written assert message can go stale against the assert it
describes; the assert's own text cannot.

IF YOU ARE MUTATION-TESTING THESE GUARDS, READ THIS SECOND PART.
================================================================

The way to know a guard can fail is to break the code and watch it fire. The
way that goes wrong is subtle and cost a wrong conclusion on 2026-08-28: a
harness that counts `FAIL` lines in stdout scores a CRASHED run and a PASSING
run identically, because both produce zero of them. A mutation that is a syntax
error therefore reads as "the guard caught nothing" — which is the precise
opposite of what happened, and it points the author at rewriting a guard that
was fine.

    Count the RETURN CODE and the emptiness of stdout, not just FAIL lines.
    A mutation run that printed nothing did not pass; it did not run.

The general form is worth stating because it is why this family keeps
recurring: **the checking layer gets written with less suspicion than the layer
being checked, because it is "just the harness".** The instrument built that
day to catch instruments whose reach is invisible had, itself, an invisible
reach. Six instances of that shape were found across the repo in one day and
the seventh was in the test rig for the fix to the sixth.
"""

import linecache
import traceback


def fail_detail(exc):
    """A never-empty, never-misleading detail string for a failed devtest case.

    A message the author wrote wins -- they know why the check exists. With no
    message, fall back to `<file>:<line>: <source>` from the DEEPEST frame of the
    traceback, which is the assert itself rather than the runner that caught it.
    """
    msg = str(exc).strip()
    if msg:
        return msg

    tb = traceback.extract_tb(exc.__traceback__)
    if not tb:
        return f"{type(exc).__name__} with no message and no traceback"

    frame = tb[-1]
    src = (frame.line or linecache.getline(frame.filename, frame.lineno)).strip()
    where = f"{frame.filename.rsplit('/', 1)[-1]}:{frame.lineno}"
    kind = type(exc).__name__
    return f"{kind} with no message — {where}: {src}" if src else \
           f"{kind} with no message — {where}"
