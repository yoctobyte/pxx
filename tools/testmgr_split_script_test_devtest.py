#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a shell script handed the compiler is its own job, never a prologue.

split_jobs() makes a target's leading group a PROLOGUE when it holds no
compiler invocation, and every other job in the target then depends on it
(it is meant for setup: rm, mkdir, the source-stamp check). A line like

    sh test/nilpy_str_default_bss.sh ./compiler/pascal26 /tmp

compiles inside the script, so COMPILE_RE cannot see it. Four of these opened
test-nilpy and so became test-nilpy#00, a 50-65 s gate for 1119 jobs. On seven,
at 688fa4b898 under full-tier load, it ran past its 90 s budget and the whole
target reported as "not run". test-core#00 held two the same way, ahead of
2534 jobs.

Measured on plexus, at load ~20, running `testmgr --tier full --job
'test-nilpy#00'` on the same tree: 64.9 s with the old split, 1.7 s with this
one. What remains in #00 is the source-stamp check the prologue exists for.

Run: tools/testmgr_split_script_test_devtest.py   (exit 0 = pass)
"""
import os
import sys
import types

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from devtest_report import fail_detail  # noqa: E402

fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name
          + (("\n         " + str(detail)) if detail and not cond else ""))
    if not cond:
        fails.append(name)


def load():
    """testmgr compiled from source text — never through __pycache__.

    A size-preserving negative control inside one second leaves the cache
    valid, so the tree restores and the behaviour does not. Measured
    2026-08-30; see tools/twatch_failing_step_devtest.py for the full note.
    """
    path = os.path.join(HERE, "testmgr.py")
    mod = types.ModuleType("tm_probe")
    mod.__file__ = path
    argv = sys.argv
    sys.argv = ["testmgr.py"]
    try:
        exec(compile(open(path).read(), path, "exec"), mod.__dict__)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return mod


tm = load()
T = tm.TESTTMP



import re  # noqa: E402
# The devtest's OWN spelling of "a script handed the compiler", so it judges
# testmgr's behaviour rather than reading testmgr's regex back to itself.
SCRIPT = re.compile(r"^(?:sh|bash)\s+\S+\.sh\s+\.?/?compiler/pascal26\b")


def names(jobs):
    return ["\n".join(l for l in j.lines if not l.strip().startswith("#"))[:60]
            for j in jobs]


# --- 1-2. the real targets ------------------------------------------------
for tgt in ("test-nilpy", "test-core"):
    jobs = tm.split_jobs(tgt, tm.make_dry_run(tgt))
    pro = jobs[0]
    gated = sum(1 for j in jobs if pro in j.deps)
    scripts_in_pro = [l for l in pro.lines if SCRIPT.match(l.strip())]
    check("%s: no script test sits in the prologue that %d jobs wait for"
          % (tgt, gated), not scripts_in_pro, scripts_in_pro)
    alone = [j for j in jobs if any(SCRIPT.match(l.strip()) for l in j.lines)]
    check("%s: every script test is a job of its own (one script line each)"
          % tgt,
          alone and all(sum(1 for l in j.lines
                            if not l.strip().startswith("#")) == 1 for j in alone),
          [j.lines for j in alone if sum(1 for l in j.lines
                                         if not l.strip().startswith("#")) != 1])


# --- 3-6. the rule on synthetic recipes -----------------------------------
def split(lines):
    return tm.split_jobs("synth", lines)


s = ["rm -f %s/x.log" % T,
     "sh test/a.sh ./compiler/pascal26 %s" % T,
     "sh test/b.sh ./compiler/pascal26 %s" % T,
     "./compiler/pascal26 test/c.pas %s/c26" % T,
     "%s/c26 | diff -u test/c.expected -" % T]
js = split(s)
check("3. setup, two scripts, one compile/check pair -> four jobs",
      len(js) == 4, names(js))
check("4. only the SETUP line is the prologue, and the scripts depend on it",
      js[0].lines == [s[0]] and all(js[0] in j.deps for j in js[1:]),
      [j.lines for j in js])

s2 = ["# what the first script checks",
      "sh test/a.sh ./compiler/pascal26 %s" % T,
      "./compiler/pascal26 test/c.pas %s/c26" % T,
      "%s/c26" % T]
js2 = split(s2)
check("5. a comment above a leading script travels with it; no comment-only "
      "prologue gates the target",
      len(js2) == 2 and js2[0].lines == s2[:2] and not js2[1].deps,
      [(j.lines, [d.lines for d in j.deps]) for j in js2])

s3 = ["sh -c 'echo hi' %s" % T,
      "./compiler/pascal26 test/c.pas %s/c26" % T,
      "%s/c26" % T]
js3 = split(s3)
check("6. a shell line NOT handed the compiler is still ordinary setup",
      len(js3) == 2 and js3[0] in js3[1].deps, [j.lines for j in js3])

print("\n%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
