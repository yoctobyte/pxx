#!/usr/bin/env python3
"""Gate for feature-t-autoticket-must-close-its-own-stubs-when-fixed.

Scratch bare repo + a clone, no compiler, no long runs (Track T's own rule for
testing its tooling). Drives close_stub_tickets directly against a real git
clone so the publish/rename path is exercised, not mocked.

Cases:
  1. stub in backlog/, job green      -> moved to done/, log line, pushed
  2. stub CLAIMED into working/       -> untouched
  3. stub body rewritten by a triager -> untouched (marker gone)
  4. cascade closes only when every swept job is green (reg_open, no I/O)
"""
import json, os, subprocess, sys, tempfile, shutil

sys.path.insert(0, "/home/neo/pxx/tools")
import twatch

WORK = tempfile.mkdtemp(prefix="twatch-stubgate-")
BARE = os.path.join(WORK, "origin.git")
CLONE = os.path.join(WORK, "clone")


def git(*a, cwd=CLONE):
    return subprocess.run(["git"] + list(a), cwd=cwd, check=True,
                          capture_output=True, text=True).stdout


STUB = """---
prio: 70
---

# %s: %s red at deadbeef1234 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.

## Repro
`tools/testmgr.py --tier full --job '%s'` at deadbeef1234

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
"""


def setup():
    subprocess.run(["git", "init", "--quiet", "--bare", "-b", "master", BARE],
                   check=True)
    subprocess.run(["git", "clone", "--quiet", BARE, CLONE], check=True)
    git("config", "user.email", "gate@test")
    git("config", "user.name", "gate")
    for b in twatch.PROGRESS_BUCKETS:
        os.makedirs(os.path.join(CLONE, "devdocs/progress", b), exist_ok=True)
    os.makedirs(os.path.join(CLONE, twatch.TSTATE_REL), exist_ok=True)
    # tickets, one per case
    def put(bucket, slug, body):
        p = os.path.join(CLONE, "devdocs/progress", bucket, slug + ".md")
        open(p, "w").write(body)
    put("backlog", "regression-test-core-alpha",
        STUB % ("test-core#src:test/alpha.pas", "test/alpha.pas",
                "test-core#src:test/alpha.pas"))
    put("working", "regression-test-core-beta",
        STUB % ("test-core#src:test/beta.pas", "test/beta.pas",
                "test-core#src:test/beta.pas"))
    put("backlog", "regression-test-core-gamma",
        "---\nprio: 70\ntrack: N\n---\n\n# gamma: root-caused by a triager\n\n"
        "Real analysis lives here now; the stub text is gone.\n")
    open(os.path.join(CLONE, twatch.TSTATE_REL, "keep"), "w").write("x\n")
    git("add", "-A")
    git("commit", "--quiet", "-m", "gate fixture")
    git("push", "--quiet", "origin", "master")


class FakeClone:
    """Enough of twatch.Clone for close_stub_tickets: a path, a branch, and a
    real publish (the rename staging is the part most likely to be wrong)."""
    path, branch = CLONE, "master"

    def publish(self, message, paths=None):
        return twatch.Clone.publish(self, message, paths)

    def _pull_rebase(self, resolve_index=False):
        return twatch.Clone._pull_rebase(self, resolve_index)

    def _drop_to_origin(self, why):
        return twatch.Clone._drop_to_origin(self, why)

    def _record_pub(self, *a, **k):
        pass


def bucket_of(slug):
    for b in twatch.PROGRESS_BUCKETS:
        if os.path.exists(os.path.join(CLONE, "devdocs/progress", b,
                                       slug + ".md")):
            return b
    return None


fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + (" — " + detail if detail and not cond else ""))
    if not cond:
        fails.append(name)


def main():
    setup()
    closed = [
        {"job": "test-core#src:test/alpha.pas", "bad": "aaaaaaaaaaaa1111"},
        {"job": "test-core#src:test/beta.pas", "bad": "bbbbbbbbbbbb2222"},
        {"job": "test-core#src:test/gamma.pas", "bad": "cccccccccccc3333"},
        {"job": "test-core#src:test/never-filed.pas", "bad": "dddddddddddd4444"},
    ]
    # A production report always carries "jobs" (testmgr writes it, run_gate
    # passes it straight through), and close_stub_tickets came to depend on it
    # for the "this source is still red in ANOTHER job" branch. The fixture did
    # not follow, so this devtest has been dying on a KeyError rather than
    # testing anything. Keep the fixture's keys matched to the real contract.
    report = {"tier": "full", "jobs": []}
    print("case 1-3: close_stub_tickets")
    twatch.close_stub_tickets(FakeClone(), "xeon", closed, "ffff5555ffff6666",
                              report)

    check("1. green stub moved backlog -> done",
          bucket_of("regression-test-core-alpha") == "done",
          "is in %s" % bucket_of("regression-test-core-alpha"))
    body = open(os.path.join(CLONE, "devdocs/progress/done",
                             "regression-test-core-alpha.md")).read()
    check("1. log line cites the passing sha and the tier",
          "ffff5555ffff" in body and "tier full" in body)
    check("1. log line cites the sha it was red at", "aaaaaaaaaaaa" in body)
    check("1. progress.sh check's commit rule satisfied",
          __import__("re").search(r"commit|[0-9a-f]{7,40}", body, 2) is not None)

    check("2. claimed stub in working/ untouched",
          bucket_of("regression-test-core-beta") == "working")
    check("3. triaged body (marker gone) untouched",
          bucket_of("regression-test-core-gamma") == "backlog")

    # the move must be on ORIGIN, not just locally: staging only the
    # destination would leave the stub in backlog upstream
    ls = subprocess.run(["git", "ls-tree", "-r", "--name-only",
                         "master", "devdocs/progress/"], cwd=BARE,
                        capture_output=True, text=True).stdout
    check("1. pushed: done/ on origin", "done/regression-test-core-alpha.md" in ls)
    check("1. pushed: backlog copy GONE on origin",
          "backlog/regression-test-core-alpha.md" not in ls, ls)

    print("case 5: a 0-byte ticket must not suppress filing")
    pdir = os.path.join(CLONE, "devdocs/progress")
    open(os.path.join(pdir, "backlog", "regression-test-core-empty.md"), "w").close()
    check("5. zero-byte ticket does NOT count as filed",
          twatch.already_filed(pdir, "regression-test-core-empty") is False)
    check("5. a real ticket still counts as filed",
          twatch.already_filed(pdir, "regression-test-core-gamma") is True)

    print("case 6: ticket writes are atomic")
    target = os.path.join(pdir, "backlog", "regression-atomic-probe.md")
    twatch.write_ticket(target, "---\nprio: 70\n---\n\nbody\n")
    check("6. content lands whole", open(target).read().endswith("body\n"))
    leftovers = [f for f in os.listdir(os.path.join(pdir, "backlog"))
                 if f.startswith(".tkt-")]
    check("6. no temp file left behind", not leftovers, leftovers)
    try:
        twatch.write_ticket(target, None)          # provoke a mid-write failure
    except TypeError:
        pass
    check("6. a failed write leaves the previous content intact",
          open(target).read().endswith("body\n"))
    leftovers = [f for f in os.listdir(os.path.join(pdir, "backlog"))
                 if f.startswith(".tkt-")]
    check("6. a failed write cleans up its temp file", not leftovers, leftovers)

    print("case 4: cascade closes only when every swept job is green")
    casc = {"job": "cascade@abc", "cascade": ["j1", "j2"], "bad": "abc"}
    one_green = {"j1": "pass", "j2": "fail"}
    all_green = {"j1": "pass", "j2": "pass"}
    # reg_open dropped its `fixed` parameter — the merged status map answers the
    # question on its own, and `fixed` (red->pass transitions THIS host saw)
    # could never close an entry migrated from a retired host. These calls were
    # still passing it POSITIONALLY, so the list landed in `authoritative` and
    # the status map in `gone`: every job read as gone, the generator emptied,
    # and the cascade closed for a reason that had nothing to do with the test.
    check("4. one lucky job green keeps the cascade OPEN",
          twatch.reg_open(casc, one_green) is True)
    check("4. every job green closes it",
          twatch.reg_open(casc, all_green) is False)

    print()
    if fails:
        print("FAILED: " + ", ".join(fails))
    else:
        print("all gate checks passed")
    shutil.rmtree(WORK, ignore_errors=True)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
