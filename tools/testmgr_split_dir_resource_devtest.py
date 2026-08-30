#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a producer that names a DIRECTORY and a consumer that names a file
inside it must land in one job.

regression-test-core-expect-same. split_jobs() starts a new job at a compiler
invocation that follows a non-compile line, then repairs the producer/consumer
edges it just cut by union-find over shared scratch paths. That repair keyed on
EXACT PATH EQUALITY, and the C include-nesting test is the shape it cannot see:

    @python3 -c "...makedirs(d)... write g0.h..g15.h and gmain.c" $(TESTTMP)/cnest16
    ./$(COMPILER) $(TESTTMP)/cnest16/gmain.c $(TESTTMP)/cnest16_26

The second line is a compile following a non-compile, so the split cuts between
them. Their token sets are {/tmp/cnest16} and {/tmp/cnest16/gmain.c,
/tmp/cnest16_26}: no string in common, so nothing merged them and the two jobs
had no ordering between them.

IT WAS A RACE, WHICH IS WHY IT PASSED FOR SO LONG. The producer's job is
dispatched first in job order, so it usually wins; on a busy box it stopped
winning. Reproduced exactly, in isolation, at the sha this landed:

    pascal26: error: cannot read input file: .../cnest16/gmain.c

against a job the harness had named `test-core#src:tools/expect_same.sh@276` --
after the job's first source, which is the harness driver.

THE BOUND IS THE PART TO GUARD. Every ancestor directory STRICTLY BELOW TESTTMP
becomes a token; TESTTMP itself must not, because every job in a target names
something under it and one token there merges the entire target into a single
job. Measured before the rule was added: across test-core, test-threads,
lib-test, test-nilpy and test-asm there are exactly THREE paths with a
subdirectory component at all, so this is a named blind spot being closed, not
a widened net -- test-core went 1599 -> 1598 jobs and no other target moved.

Run: tools/testmgr_split_dir_resource_devtest.py   (exit 0 = pass)
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


def job_of(jobs, needle):
    return next((j for j in jobs if needle in "\n".join(j.lines)), None)


# --- 1. the ticket's own case, against the real Makefile ------------------
jobs = tm.split_jobs("test-core", tm.make_dry_run("test-core"))
j = job_of(jobs, "cnest16")
produces = j and any("makedirs" in l and "cnest16" in l for l in j.lines)
consumes = j and any("cnest16/gmain.c" in l and "pascal26" in l for l in j.lines)
check("1. the cnest16 generator and the compile that reads its output are in "
      "ONE job",
      bool(produces and consumes),
      "job %s: producer=%s consumer=%s — two jobs have no ordering, and the "
      "consumer then runs against a scratch dir the producer never filled"
      % (j.name if j else None, produces, consumes))
check("1b. and only ONE job holds cnest16 — a second would mean the split "
      "cut it somewhere else",
      sum(1 for x in jobs if "cnest16" in "\n".join(x.lines)) == 1,
      [x.name for x in jobs if "cnest16" in "\n".join(x.lines)])


# --- 2-4. the rule, and its bound, on synthetic recipes -------------------
def split(lines):
    return tm.split_jobs("synth", lines)


mk = ["mkdir -p %s/wsp && python3 gen.py %s/wsp" % (T, T),
      "./compiler/pascal26 %s/wsp/main.c %s/out26" % (T, T),
      "%s/out26 | diff -u test/x.expected -" % T]
check("2. a group naming <TESTTMP>/dir and a later group naming "
      "<TESTTMP>/dir/file are merged",
      len(split(mk)) == 1, [g.lines for g in split(mk)])

# The bound. Without it TESTTMP itself becomes a shared token and every job in
# a target collapses into one, because they all name something under it.
# Two chains that share NO scratch path and only their parent directory. The
# first fixture written for this had a producer line for chain B sitting inside
# chain A's group, which chained all three groups through it -- and it merged
# identically BEFORE the fix, which is how it was caught: when a guard fails,
# the first question is whether it fails pre-fix too.
mk2 = ["./compiler/pascal26 test/a.pas %s/alpha26" % T,
       "%s/alpha26 > %s/alpha.out" % (T, T),
       "./compiler/pascal26 test/b.pas %s/beta26" % T,
       "%s/beta26 > %s/beta.out" % (T, T)]
check("3. THE BOUND: two independent chains that merely both live under "
      "TESTTMP are NOT merged",
      len(split(mk2)) == 2,
      "%d job(s); TESTTMP itself must never become a token — one there merges "
      "the whole target" % len(split(mk2)))

# nested deeper than one level, and the ancestor walk must stop at TESTTMP
mk3 = ["mkdir -p %s/a/b/c && python3 gen.py %s/a/b/c" % (T, T),
       "./compiler/pascal26 %s/a/b/c/main.c %s/deep26" % (T, T),
       "%s/deep26" % T]
check("4. the ancestor walk reaches a grandparent directory too",
      len(split(mk3)) == 1, [g.lines for g in split(mk3)])

# --- 5. the edge the ancestor rule must not have broken -------------------
mk4 = ["gcc -shared -o %s/libspill.so spill.c" % T,
       "./compiler/pascal26 test/user.pas %s/user26" % T,
       "LD_LIBRARY_PATH=%s %s/user26" % (T, T)]
check("5. the pre-existing .so / LD_LIBRARY_PATH edge still merges — the "
      "loader finds the library by soname, sharing no filename",
      len(split(mk4)) == 1, [g.lines for g in split(mk4)])

print("\n%d check(s), %d FAILED" % (6, len(fails)))
sys.exit(1 if fails else 0)
