#!/usr/bin/env python3
"""Devtest: T verifies the PINNED sha, not just HEAD.

task-t-pin-fast-track-t-owns-verification — the "suggested shape" bullet that
was never built:

    T may treat "a new sha appeared in pin.log" as a trigger to run tier 1
    against it promptly, so the pin the tracks are actually using is the one
    that gets attention first.

Why it matters, measured 2026-08-11 over pin.log x runs-*.ndjson: **18 of the
last 25 pins never received a `full` run, and 13 were never judged in ANY
tier.** The escalation ladder deepens HEAD, and a pin is whatever HEAD happened
to be when a human ran `make pin` — so by the time the box climbs to depth, the
pin is history. The artifact every other track builds on (`$(PXX_STABLE)`) was
the one sha nobody was deepening, which voids the recovery half of the fast-pin
trade: a bad pin is meant to be RECOVERED rather than prevented, and recovery
needs a verdict.

Covered here: the pin.log parse (both line shapes), the "already judged" skip,
the mid-before-deep split that keeps native depth ahead of platform breadth,
and the unreachable-pin guard.

Run: tools/devtest_pin_verify.py   (exit 0 = pass)
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

fails = []


def check(cond, what, detail=""):
    print("  %-4s %-52s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


# Two shapes genuinely live in pin.log: older lines omit the binary sha256.
# The GIT sha is last in both, which is why the parser counts from the END.
OLD = "2026-07-01T10:00:00Z  pinned v9 (was v9)  " + "a" * 40
NEW = ("2026-08-10T14:03:09Z  pinned v256  " + "d" * 64 +
       "  (was 259f2580d97f)  " + "c" * 40)


class FakeClone:
    """Just enough of Clone for pinned_ref/judged_tiers: a real git repo whose
    origin/<branch> carries a pin.log, plus a tstate dir."""

    def __init__(self, path, log_lines, head=None):
        self.path = path
        self.branch = "master"
        self._head = head or ("c" * 40)
        d = os.path.join(path, os.path.dirname(tw.PIN_LOG_REL))
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(path, tw.PIN_LOG_REL), "w") as f:
            f.write("\n".join(log_lines) + "\n")
        os.makedirs(os.path.join(path, tw.TSTATE_REL), exist_ok=True)

    def remote_head(self):
        return self._head


def git(repo, *args):
    subprocess.run(["git"] + list(args), cwd=repo, check=True,
                   capture_output=True)


def make_repo(tmp, log_lines):
    """A clone with a real origin/master carrying pin.log, so pinned_ref's
    `git show origin/master:...` is exercised for real rather than stubbed.

    The upstream is BARE: the clone pushes back to it in the ordering tests, and
    a non-bare origin with master checked out refuses that push.
    """
    up = os.path.join(tmp, "up.git")
    os.makedirs(up)
    git(up, "init", "--quiet", "--bare", "-b", "master")
    seed = os.path.join(tmp, "seed")
    os.makedirs(seed)
    git(seed, "init", "--quiet", "-b", "master")
    git(seed, "config", "user.email", "t@example.com")
    git(seed, "config", "user.name", "t")
    d = os.path.join(seed, os.path.dirname(tw.PIN_LOG_REL))
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(seed, tw.PIN_LOG_REL), "w") as f:
        f.write("\n".join(log_lines) + "\n")
    git(seed, "add", "-A")
    git(seed, "commit", "--quiet", "-m", "pin")
    git(seed, "remote", "add", "origin", up)
    git(seed, "push", "--quiet", "origin", "master")
    clone = os.path.join(tmp, "clone")
    git(tmp, "clone", "--quiet", up, clone)
    git(clone, "config", "user.email", "t@example.com")
    git(clone, "config", "user.name", "t")
    os.makedirs(os.path.join(clone, tw.TSTATE_REL), exist_ok=True)
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=clone,
                          capture_output=True, text=True).stdout.strip()
    return clone, head


def write_runs(clone, host, rows):
    with open(os.path.join(clone, tw.TSTATE_REL, "runs-%s.ndjson" % host),
              "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")


def main():
    tmp = tempfile.mkdtemp(prefix="devtest-pinverify-")
    print("pin.log parsing (the file has two line shapes)")
    clone_path, head = make_repo(tmp, [OLD, NEW])

    class C:
        path = clone_path
        branch = "master"

        def remote_head(self):
            return head
    c = C()
    got = tw.pinned_ref(c)
    check(got == ("v256", "c" * 40), "reads the LAST pin, newer line shape",
          str(got))

    clone2, _ = make_repo(tempfile.mkdtemp(prefix="devtest-pinverify2-"), [OLD])
    class C2:
        path = clone2
        branch = "master"
    check(tw.pinned_ref(C2()) == ("v9", "a" * 40),
          "older line shape (no binary sha) still parses",
          "the git sha is last in BOTH shapes")

    class C3:
        path = tmp          # a dir that is not a git repo
        branch = "master"
    check(tw.pinned_ref(C3()) is None, "no pin.log -> None, never a crash",
          "a fresh clone must not wedge the daemon")

    print("\nwhat is due, and in which order")
    host = "plexus"
    st = {}
    # Make the pin name a sha that REALLY EXISTS in this repo, so the
    # reachability guard is exercised against real git rather than a stub.
    with open(os.path.join(clone_path, tw.PIN_LOG_REL), "w") as f:
        f.write("2026-08-10T14:03:09Z  pinned v256  %s  (was x)  %s\n"
                % ("d" * 64, head))
    git(clone_path, "commit", "--quiet", "-am", "repin")
    git(clone_path, "push", "--quiet", "origin", "master")
    head2 = subprocess.run(["git", "rev-parse", "HEAD"], cwd=clone_path,
                           capture_output=True, text=True).stdout.strip()

    class CH:
        path = clone_path
        branch = "master"

        def remote_head(self):
            return head2
    ch = CH()

    write_runs(clone_path, host, [])
    due = tw.pin_verify_due(ch, host, st, ("limited",))
    check(due is not None and due[2] == "limited",
          "unjudged pin -> limited is due", str(due))

    write_runs(clone_path, host, [{"sha": head, "tier": "limited",
                                   "verdict": "GREEN"}])
    check(tw.pin_verify_due(ch, host, st, ("limited",)) is None,
          "already judged at limited -> not due again",
          "or the box would re-verify the same pin forever")
    due = tw.pin_verify_due(ch, host, st, ("full",))
    check(due is not None and due[2] == "full",
          "...but breadth on the same pin IS still due",
          "pinstatus needs a `full` run to name a fallback")

    write_runs(clone_path, host, [{"sha": head, "tier": "limited",
                                   "verdict": "GREEN"},
                                  {"sha": head, "tier": "full",
                                   "verdict": "GREEN"}])
    check(tw.pin_verify_due(ch, host, st, ("limited",)) is None
          and tw.pin_verify_due(ch, host, st, ("full",)) is None,
          "both tiers judged -> nothing due", "the phase must terminate")

    print("\nguards")
    class CU:
        path = clone_path
        branch = "master"

        def remote_head(self):
            return "f" * 40        # a head this clone does not have
    write_runs(clone_path, host, [])
    check(tw.pin_verify_due(CU(), host, st, ("limited",)) is None,
          "pin unreachable from head -> skip, do not checkout",
          "another box may have pushed a pin we have not fetched")

    check(tw.judged_tiers(ch, "nosuchhost", head) == set(),
          "no run archive for a host -> empty, not a crash")

    print("\n%s" % ("FAILED: " + ", ".join(fails) if fails else "all pass"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
