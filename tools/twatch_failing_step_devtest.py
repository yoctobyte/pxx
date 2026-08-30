#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: an auto-filed stub routes on the step that BROKE, not the job's name.

bug-t-a-job-named-after-its-first-source-file-cannot-name-its-failing-step.

A job is a SCRIPT, not a test. `lib-test#00` is 198 recipe lines naming 39
source files across Tracks A, B, C and T; the job's name and its `src` field
both come from the FIRST of those, which is related to the failure only by
which file happened to be first. Three reds in that one job were filed
`track: C` off `tools/crtl_reachability.py` while the red was a GTK3 guard in
`lib/pcl` twenty lines down -- Track B, retracked by hand each time.

Measured, at the sha this landed:

  step 17 `python3 tools/crtl_reachability.py`     -> C   (job guess: C)
  step 22 `python3 tools/gen_crtl_map.py --check`  -> C   (job guess: C)
  step 28 `python3 tools/lib_units_compile.py`     -> B   (job guess: C)  <-- -4

THE TICKET'S FIRST PROPOSAL IS REFUTED, not adopted. It asked for the SLUG to
be built from the failing step. The slug cannot move, for two structural
reasons the code makes checkable rather than arguable:

  * it is the dedupe key AND the close key, and the two are computed at
    different times from different data. `stub_slug_for_filing()` derives it
    from the job when FILING; `close_stub_tickets()` recomputes it from
    `reg_slug(r["job"])` when CLOSING, where no step is in scope. A
    step-derived slug is therefore unfindable at close time -- every stub
    would leak open, silently, which is the failure mode
    feature-t-autoticket-must-close-its-own-stubs-when-fixed existed to end.
  * `progress.py` derives a ticket's TYPE from the slug's first token, so
    `regression-lib-units-pcl-gtk3` would become a ticket of type `lib`.

And a step-derived slug is not stable ACROSS RUNS: one broken job that fails
at a different line tomorrow files a second ticket for one defect, which is
precisely what the stable-selector slug was introduced to stop.

So the step lands in the three places that are free to move -- the `track:`
frontmatter (what the ranker routes on), the H1 (what the board prints, since
a stub carries no `summary:`), and a body bullet -- and the slug stays put.

The guards below are therefore about EVIDENCE and its BOUNDS:

  * the failing step is READ from a marker, never inferred from the log;
  * a comment line can never be named as the failing step;
  * the step's sources are the step's own -- the job's are not consulted;
  * ...except where the job has exactly ONE source, where first-source and
    only-source are the same file and there is no other lane in frame. Without
    that bound the whole single-test majority (`compile foo.pas`, then `diff
    foo.expected -`, whose failing step names only the .expected) would have
    been routed to T;
  * a report from an older watcher, with no step fields at all, keeps today's
    behaviour rather than crashing or refusing;
  * the `- **Test source:**` line stays byte-parseable by twatch's own SRC_RE,
    because close_stub_tickets reads it to decide whether a source is still
    red elsewhere;
  * TWO stubs are filed in one batch -- a one-job fixture cannot see a
    variable shadowing the state dict, which is a crash that only reaches the
    second iteration.

Run: tools/twatch_failing_step_devtest.py   (exit 0 = pass)
"""
import os
import subprocess
import sys
import tempfile
import types

# NO BYTECODE CACHE, IN EITHER DIRECTION -- and this is not hygiene, it is a
# measured instrument failure. CPython validates a `__pycache__` entry against
# the source's (mtime, size) with mtime at ONE-SECOND resolution. A negative
# control that edits a module in place, runs, and restores it is therefore
# invisible to that check whenever the edit is SIZE-PRESERVING and the whole
# cycle fits inside one second -- `if stepf:` -> `if False:` is five characters
# for five. That happened here: the control restored testmgr.py byte for byte,
# sha256 confirmed it, and every later run silently executed the CONTROL's
# bytecode. Guard 1 then failed against a correct tree, in three consecutive
# runs, with the source verifiably right in front of me.
#
# It is the exact inverse of the empty-red problem: there, a broken control
# reports maximum sensitivity; here, a restored tree reports a defect that is
# no longer in it. Both are read as findings. A sha check on the SOURCE proves
# nothing about what will EXECUTE, so this file compiles what it measures from
# text and writes no cache of its own.
sys.dont_write_bytecode = True
sys.path.insert(0, "/home/neo/pxx/tools")
import twatch  # noqa: E402

REPO = "/home/neo/pxx"
WORK = tempfile.mkdtemp(prefix="twatch-stepgate-")
BARE = os.path.join(WORK, "origin.git")
CLONE = os.path.join(WORK, "clone")

fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name
          + (("\n         " + detail) if detail and not cond else ""))
    if not cond:
        fails.append(name)


def load_testmgr():
    """testmgr as a module, compiled from its source text — never via a cache.

    See the note at the top of this file: the loader path consults
    `__pycache__` keyed on second-resolution mtime plus size, which a
    size-preserving negative control defeats.
    """
    path = os.path.join(REPO, "tools", "testmgr.py")
    with open(path) as f:
        src = f.read()
    mod = types.ModuleType("tm_probe")
    mod.__file__ = path
    argv = sys.argv
    sys.argv = ["testmgr.py"]
    try:
        exec(compile(src, path, "exec"), mod.__dict__)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return mod


tm = load_testmgr()


# --- 1/2. the marker: read, not inferred; and never a comment --------------
def run_synthetic_job():
    d = tempfile.mkdtemp(prefix="stepmark-", dir=WORK)
    lines = ["true",
             "# a recipe comment, which make treats as a shell no-op",
             "echo built test/alpha.pas into /tmp/alpha",
             "lib/pcl/gtk3_guard.pas-check-that-does-not-exist",
             "echo this line never runs"]
    j = tm.Job("faketgt", 0, lines)
    j.logpath = os.path.join(d, "faketgt_00.log")
    rc = subprocess.run(["sh", "-c", j.script()], cwd=REPO,
                        capture_output=True, text=True)
    return j, rc


job, rc = run_synthetic_job()
i, line = tm.failed_step(job)
check("1. the failing step is READ back, and it is the line that failed",
      i == 3 and "gtk3_guard" in line,
      "got index %r, line %r (rc=%d)" % (i, line, rc.returncode))
check("2. a comment line is never named as the failing step "
      "(index 1 is a `#` line and the marker skips it)",
      "echo 1 > " not in job.script(),
      "script writes a marker for the comment line:\n%s" % job.script())


# --- 3. the step's sources are the step's own -----------------------------
step3 = tm.step_sources(job.lines[3])
check("3. step_sources reads ONLY the given line, never the job's other "
      "sources",
      step3.startswith("lib/pcl/") and "test/alpha.pas" not in step3,
      "step 3 -> %r ; job src -> %r" % (step3, job.src))
check("3b. and the job's OWN src still names the first file, which is the "
      "thing we are refusing to route on",
      "test/alpha.pas" in (job.src or ""), "job.src = %r" % job.src)


# --- 3c. the marker must never become the thing that reports ---------------
#
# STATUS PROVENANCE, and this guard exists because the step marker is exactly
# the shape that breaks it: anything appended AFTER the thing you are measuring
# becomes the thing that reports. `cmd > log; tail log` reports tail's status,
# `cmd | tee` reports tee's, and a `;`-list reports its last command's -- each
# layer answering correctly about what it was given, failing in the
# green-looking direction. Found fleet-wide 2026-08-30; a pin that failed the
# self-host fixedpoint was notified as exit 0.
#
# script() writes the marker BEFORE each recipe line, never after, so a job's
# exit status is still the first failing recipe line's. That is a property of
# the emission order and nothing enforces it but this check. Measured over
# every job in five targets rather than argued: 2653 scripts, 0 whose last
# command is anything but a recipe line.
bad = []
for tgt in ("test-core", "test-threads", "lib-test", "test-nilpy", "test-asm"):
    for jj in tm.split_jobs(tgt, tm.make_dry_run(tgt)):
        jj.logpath = "/nonexistent/%s.log" % jj.name.replace("/", "_")
        last = jj.script().rstrip("\n").splitlines()[-1]
        if not last.endswith("|| exit $?"):
            bad.append((jj.name, last[:90]))
check("3c. no job's script ends in a step marker — the marker is emitted "
      "BEFORE each line, so it can never become the command that reports "
      "the job's status",
      not bad, "%d job(s), e.g. %s" % (len(bad), bad[:3]))


# --- 4-8. routing ---------------------------------------------------------
def rec(**kw):
    base = {"status": "fail", "src": "", "step_i": None, "step_n": 0,
            "step_line": "", "step_src": ""}
    base.update(kw)
    return base


t, note = twatch.stub_track(rec(
    src="test/crtl_reachability.c tools/gen_crtl_map.py +37",
    step_i=28, step_n=198,
    step_line="PXX_STABLE=stable/pinned python3 tools/lib_units_compile.py",
    step_src="tools/lib_units_compile.py"))
check("4. THE TICKET'S CASE: a job whose first source says C, failing in a "
      "step that says B, is filed B",
      t == "B" and "FAILING STEP" in note,
      "got track %r; note: %s" % (t, note[:200]))

t, note = twatch.stub_track(rec(
    src="test/alpha.pas", step_i=1, step_n=2,
    step_line="/tmp/alpha | diff -u test/alpha.expected -",
    step_src="test/alpha.expected"))
check("5. THE BOUND: a job with ONE source whose failing step names no lane "
      "keeps that source's track (P), it is not swept to T",
      t == "P" and "only ONE source" in note,
      "got track %r; note: %s" % (t, note[:240]))

t, note = twatch.stub_track(rec(
    src="test/crtl_reachability.c tools/gen_crtl_map.py +37",
    step_i=125, step_n=198,
    step_line='n=$(readelf -d /tmp/cwctype | grep -c NEEDED); test "$n" = "0"',
    step_src=""))
check("6. a MULTI-source job whose failing step names no lane refuses to "
      "guess: T, and it says the job's src was deliberately not used",
      t == "T" and "NOT used here on purpose" in note,
      "got track %r; note: %s" % (t, note[:240]))

t, note = twatch.stub_track(rec(src="test/alpha.pas"))
check("7. a report with NO step fields (an older watcher clone) keeps "
      "today's behaviour rather than crashing or refusing",
      t == "P" and "not recorded" in note,
      "got track %r; note: %s" % (t, note[:240]))

t, note = twatch.stub_track(rec(
    status="timeout", src="test/alpha.pas", step_i=4, step_n=9,
    step_line="qemu-aarch64 /tmp/alpha_a64", step_src=""))
check("8. a TIMEOUT still stays T, and now names the line it was sitting in",
      t == "T" and "line 5 of 9" in note,
      "got track %r; note: %s" % (t, note[:300]))


# --- 9-12. the filed ticket ----------------------------------------------
def git(*a):
    return subprocess.run(["git"] + list(a), cwd=CLONE, check=True,
                          capture_output=True, text=True).stdout


class FakeClone:
    path, branch = CLONE, "master"

    def publish(self, message, paths=None):
        return twatch.Clone.publish(self, message, paths)

    def _pull_rebase(self, resolve_index=False):
        return twatch.Clone._pull_rebase(self, resolve_index)

    def _drop_to_origin(self, why):
        return twatch.Clone._drop_to_origin(self, why)

    def _record_pub(self, *a, **k):
        pass


def setup_clone():
    subprocess.run(["git", "init", "--quiet", "--bare", "-b", "master", BARE],
                   check=True)
    subprocess.run(["git", "clone", "--quiet", BARE, CLONE], check=True)
    git("config", "user.email", "gate@test")
    git("config", "user.name", "gate")
    for b in twatch.PROGRESS_BUCKETS:
        os.makedirs(os.path.join(CLONE, "devdocs/progress", b), exist_ok=True)
    os.makedirs(os.path.join(CLONE, twatch.TSTATE_REL), exist_ok=True)
    open(os.path.join(CLONE, twatch.TSTATE_REL, "keep"), "w").write("x\n")
    git("add", "-A")
    git("commit", "--quiet", "-m", "gate fixture")
    git("push", "--quiet", "origin", "master")


setup_clone()
JOB_A = "lib-test#src:test/crtl_reachability.c"
JOB_B = "test-core#src:test/beta.pas"
jobs = [
    {"name": "lib-test#00", "sel": JOB_A, "status": "fail",
     "src": "test/crtl_reachability.c tools/gen_crtl_map.py +37",
     "step_i": 28, "step_n": 198, "step_src": "tools/lib_units_compile.py",
     "step_line": "PXX_STABLE=stable/pinned python3 tools/lib_units_compile.py",
     "log": "", "advisory": False, "pin_built": False},
    {"name": "test-core#07", "sel": JOB_B, "status": "fail",
     "src": "test/beta.pas", "step_i": 1, "step_n": 2,
     "step_src": "test/beta.expected",
     "step_line": "/tmp/beta | diff -u test/beta.expected -",
     "log": "", "advisory": False, "pin_built": False},
]
report = {"tier": "full", "jobs": jobs}
state = {"open_regressions": [
    {"job": JOB_A, "bad": "aaaaaaaaaaaa1111", "range": ["x", "y"],
     "good": "999999999999"},
    {"job": JOB_B, "bad": "bbbbbbbbbbbb2222", "first_seen": True},
]}
twatch.file_stub_tickets(FakeClone(), "gatehost", state, "aaaaaaaaaaaa1111",
                         [JOB_A, JOB_B], report)

pdir = os.path.join(CLONE, "devdocs/progress")
pa = os.path.join(pdir, "backlog", twatch.reg_slug(JOB_A) + ".md")
pb = os.path.join(pdir, "backlog", twatch.reg_slug(JOB_B) + ".md")
check("9. TWO stubs are filed in one batch — a one-job fixture cannot see a "
      "shadowed state dict, which only crashes on the second iteration",
      os.path.exists(pa) and os.path.exists(pb),
      "a=%s b=%s" % (os.path.exists(pa), os.path.exists(pb)))

body_a = open(pa).read() if os.path.exists(pa) else ""
body_b = open(pb).read() if os.path.exists(pb) else ""
check("10. the filed ticket carries `track: B` in FRONTMATTER, which is what "
      "the ranker reads",
      body_a.split("---")[1].strip().splitlines()[-1].strip() == "track: B",
      "frontmatter: %r" % body_a.split("---")[1] if body_a else "no ticket")
check("11. the H1 — the line the board prints, since a stub has no "
      "`summary:` — names the failing step",
      "in step 29/198" in body_a,
      "H1: %s" % next((l for l in body_a.splitlines()
                       if l.startswith("# ")), "(none)"))
check("12. a job whose FIRST run is red is headed `first-ever red`, not "
      "`regression` — the slug still says regression- and must",
      body_b.lstrip().startswith("---")
      and "# first-ever red:" in body_b
      and twatch.reg_slug(JOB_B).startswith("regression-"),
      "H1: %s" % next((l for l in body_b.splitlines()
                       if l.startswith("# ")), "(none)"))
check("13. the `- **Test source:**` line stays byte-parseable by twatch's own "
      "SRC_RE — close_stub_tickets reads it to decide whether a source is "
      "still red in another job",
      (twatch.SRC_RE.search(body_a) or None)
      and twatch.SRC_RE.search(body_a).group(1).strip()
      == "test/crtl_reachability.c tools/gen_crtl_map.py +37",
      "captured %r" % (twatch.SRC_RE.search(body_a).group(1)
                       if twatch.SRC_RE.search(body_a) else None))
check("14. the body carries the failing step as its own bullet, adjacent to "
      "the source it disagrees with",
      "- **Failing step:** line 29 of 198" in body_a
      and "tools/lib_units_compile.py" in body_a,
      body_a)

print("\n%d check(s), %d FAILED" % (15, len(fails)))
sys.exit(1 if fails else 0)
