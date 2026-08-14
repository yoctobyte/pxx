#!/usr/bin/env python3
"""Track T devtest: every job gets a deterministic stdin.

bug-t-three-network-tests-flake-and-cost-real-debugging-time. A job that
inherits testmgr's stdin gets a different answer depending on how the run was
launched — terminal under `make`, pipe under a gate, whatever systemd hands the
watcher. test/lib_platform_esp.pas calls every Pal* entry point with fd 0 and
changes half its output accordingly, which read as a flaky network test for
weeks.

This drives the REAL `Manager.launch`, not a reconstruction of it, because the
thing being asserted is one keyword argument that a refactor could quietly drop.
launch() only touches self.logdir and self.running, so a stub `self` is enough.
"""
import os
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr as T                                            # noqa: E402

fails = []


def check(name, got, want):
    if got != want:
        fails.append("%s\n     got:  %r\n     want: %r" % (name, got, want))
    else:
        print("  ok  %s" % name)


class StubMgr:
    """Just enough of Manager for launch(): a log dir and a running list."""
    def __init__(self, logdir):
        self.logdir = logdir
        self.running = []


class StubJob:
    def __init__(self, script):
        self.name = "stdin-probe"
        self._script = script
        self.proc = None
        self.t0 = None
        self.status = "queued"
        self.attempts = 0
        self.logpath = None

    def script(self):
        return self._script


def run_probe(parent_stdin):
    """Launch a job through the real launch(), with THIS process handing the
    child a deliberately odd stdin. Returns what the job saw on fd 0."""
    d = tempfile.mkdtemp()
    mgr = StubMgr(d)
    job = StubJob("readlink /proc/self/fd/0 || echo NONE\n")
    # Point our OWN stdin at something distinctive first: if launch() forgets
    # stdin=DEVNULL the child inherits exactly this, which is the bug.
    saved = os.dup(0)
    try:
        os.dup2(parent_stdin.fileno(), 0)
        T.Manager.launch(mgr, job)
        job.proc.wait(timeout=30)
    finally:
        os.dup2(saved, 0)
        os.close(saved)
    with open(job.logpath, errors="replace") as f:
        return f.read().strip()


# --- the child must see /dev/null regardless of what the parent holds --------
with open("/etc/hostname") as regular:
    got_file = run_probe(regular)
check("parent stdin = a regular file -> child still sees /dev/null",
      got_file.endswith("/dev/null") or got_file == "/dev/null", True)

p = subprocess.Popen(["printf", "hello"], stdout=subprocess.PIPE)
got_pipe = run_probe(p.stdout)
p.wait()
check("parent stdin = a pipe -> child still sees /dev/null",
      got_pipe.endswith("/dev/null") or got_pipe == "/dev/null", True)

check("the two agree — stdin no longer varies with launch context",
      got_file == got_pipe, True)

# --- and prove the probe would actually have CAUGHT the old behaviour --------
# Without this, a probe that always passes proves nothing. Same script, same
# parent stdin, but spawned the way launch() used to: inheriting.
d = tempfile.mkdtemp()
logp = os.path.join(d, "inherit.log")
with open("/etc/hostname") as regular, open(logp, "wb") as logf:
    saved = os.dup(0)
    try:
        os.dup2(regular.fileno(), 0)
        subprocess.Popen(["sh", "-c", "readlink /proc/self/fd/0 || echo NONE"],
                         stdout=logf, stderr=subprocess.STDOUT,
                         cwd=T.REPO).wait(timeout=30)
    finally:
        os.dup2(saved, 0)
        os.close(saved)
inherited = open(logp, errors="replace").read().strip()
check("control: inheriting really does leak the parent's stdin",
      inherited.endswith("/dev/null"), False)

print()
if fails:
    print("FAIL (%d):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("devtest_job_stdin: all checks pass")
