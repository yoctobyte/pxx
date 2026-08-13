#!/usr/bin/env python3
"""Track T devtest: tools/autotriage.py against synthetic fixtures.

Exercises the three behaviours worth having: noise filtering (so "one semantic
commit" means something), lane attribution, and the reopen check -- which is the
whole reason the tool exists and the one that is easy to get silently wrong.
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import autotriage as A                                            # noqa: E402

fails = []


def check(name, got, want):
    if got != want:
        fails.append("%s\n     got:  %r\n     want: %r" % (name, got, want))
    else:
        print("  ok  %s" % name)


# --- noise filter ------------------------------------------------------------
for subj, noise in (
    ("tstate(plexus): abc GREEN (native)", True),
    ("tstate-ticket(plexus): regression-foo.md", True),
    ("docs(progress): record the shas the resolves landed as", True),
    ("feat(N): e.args, and the KeyError repr it unblocked", False),
    ("chore(A): pin v277", False),
    ("fix(P): uses order", False),
):
    check("noise? %-52s" % subj[:52], bool(A.NOISE_RE.match(subj)), noise)

# --- lane from a declared commit subject -------------------------------------
for subj, lane in (("feat(N): x", "N"), ("chore(A): y", "A"),
                   ("fix(P): z", "P"), ("docs(T): w", "T")):
    m = A.SUBJ_LANE_RE.match(subj)
    check("declared lane %-14s" % subj[:14], m.group(1).upper() if m else None, lane)

# a subject with a long parenthetical is NOT a lane tag
m = A.SUBJ_LANE_RE.match("fix(progress): something")
check("long paren is not a lane",
      bool(m and len(m.group(1)) <= 2), False)

# --- lane from paths ---------------------------------------------------------
def path_lane(f):
    for rx, lane in A.PATH_LANES:
        if rx.search(f):
            return lane
    return "?"


for f, lane in (
    ("compiler/pyparser.inc", "N"),
    ("compiler/cparser.inc", "C"),
    ("compiler/builtin/pylib.pas", "N"),
    ("compiler/ir_codegen.inc", "A"),
    ("compiler/lexer.inc", "A"),
    ("lib/rtl/sysutils.pas", "B"),
    ("tools/testmgr.py", "T"),
    ("test/foo.npy", "N"),
):
    check("path lane %-28s" % f, path_lane(f), lane)

# --- the reopen check --------------------------------------------------------
# The behaviour that mattered on 2026-08-13: a red whose test is named in an
# already-resolved ticket must surface that ticket, because the commit in range
# is then likely the trigger rather than the cause.
tmp = tempfile.mkdtemp()
os.makedirs(os.path.join(tmp, "done"))
os.makedirs(os.path.join(tmp, "backlog"))
with open(os.path.join(tmp, "done", "bug-a-old-thing.md"), "w") as f:
    f.write("---\ntrack: A\n---\n\nFixed by touching test_uses_order_pylib_exception_a.pas\n")
with open(os.path.join(tmp, "done", "bug-b-unrelated.md"), "w") as f:
    f.write("---\ntrack: B\n---\n\nnothing to do with it\n")

with open(os.path.join(tmp, "done", "bug-pascal-uses-order-breaks-pylib-exception.md"), "w") as f:
    f.write("---\ntrack: A\n---\n\nthe real owner\n")
with open(os.path.join(tmp, "backlog",
                       "regression-test-core-test-uses-order-pylib-exception-a.md"), "w") as f:
    f.write("stub\n")

JOB = "test-core#src:test/test_uses_order_pylib_exception_a.pas"
orig = A.PROGRESS
A.PROGRESS = tmp
try:
    # the stub name combines the make TARGET and the source; matching on the
    # test stem is what makes it findable (rebuilding the whole slug did not)
    check("stub_for finds the watcher's auto-filed stub",
          os.path.basename(A.stub_for(JOB) or ""),
          "regression-test-core-test-uses-order-pylib-exception-a.md")
    check("stub_for is None for an unknown job",
          A.stub_for("test-core#src:test/test_nope.pas"), None)

    # THE regression this tool exists for: the test's own header cites the
    # ticket that owns the bug. Text-matching done/ for the FILENAME instead
    # surfaced a Track N ticket that merely mentioned it, missing the Track A
    # one -- pointing at the wrong lane, which is worse than silence.
    cited = A.cited_tickets(JOB)
    check("cited_tickets reads the slug from the test's own source",
          [(c[1], c[2]) for c in cited],
          [("bug-pascal-uses-order-breaks-pylib-exception", "A")])

    mentions = A.mentioning_tickets(JOB, exclude={c[1] for c in cited})
    check("the weak filename match is reported separately, not merged",
          [m[1] for m in mentions], ["bug-a-old-thing"])

    check("no citation for a test that names no ticket",
          A.cited_tickets("test-core#src:test/test_totally_new_thing.pas"), [])
finally:
    A.PROGRESS = orig

print()
if fails:
    print("FAIL (%d):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("devtest_autotriage: all checks pass")
