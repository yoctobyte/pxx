#!/usr/bin/env python3
"""devtest: the targeted-verdict queue — parse, dedupe, and the completion rule.

The queue exists because the watcher climbs to the newest testable commit
rather than sweeping each one, so most commits never get a verdict of their own
(0 of 79 buildable commits since 2026-08-26). Its defining property is that
COMPLETION NEEDS NO WRITE: a request is satisfied when judged_tiers() reports
that tier for that sha. Nothing deletes, nothing acknowledges, two hosts can
drain the same file without coordinating, and a repeat request is a no-op.

That property is what this guards. If a future change makes the queue depend on
deletion, these fail.
"""
import json, os, subprocess, sys, tempfile, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

fails = []
checks = 0


def check(cond, what):
    global checks
    checks += 1
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)


def git(repo, *a):
    return subprocess.run(["git"] + list(a), cwd=repo, text=True,
                          capture_output=True, check=True).stdout.strip()


def main():
    with tempfile.TemporaryDirectory(prefix="twreq.") as repo:
        git(repo, "init", "-q", "-b", "master")
        git(repo, "config", "user.email", "t@example.invalid")
        git(repo, "config", "user.name", "devtest")
        shas = []
        for i in range(3):
            with open(os.path.join(repo, "f%d" % i), "w") as f:
                f.write("%d\n" % i)
            git(repo, "add", "-A")
            git(repo, "commit", "-qm", "c%d" % i)
            shas.append(git(repo, "rev-parse", "HEAD"))
        os.makedirs(os.path.join(repo, tw.TSTATE_REL), exist_ok=True)

        check(tw.read_verify_requests(repo) == [],
              "a missing queue file is empty, not an error")

        qp = os.path.join(repo, tw.VERIFY_REQ_REL)
        with open(qp, "w") as f:
            f.write("# a comment\n")
            f.write("\n")
            f.write("%s\tnative\tfrankT\tbecause\n" % shas[0])
            f.write("%s\tfull\tfrankA\t\n" % shas[1])
            f.write("garbage\n")                       # too few fields
            f.write("deadbeef\tnative\tx\ty\n")        # not a 40-char sha
            f.write("%s\tbogus-tier\tx\ty\n" % shas[2])
        got = tw.read_verify_requests(repo)
        check(len(got) == 2, "malformed rows are skipped, valid ones kept")
        check(got[0] == (shas[0], "native", "frankT", "because"),
              "fields parse in order, oldest first")
        check(got[1][2] == "frankA" and got[1][3] == "",
              "a missing why is empty, not a crash")

        # A bad row must never take the daemon down -- the file is
        # hand-editable and agent-appended, so bad rows are expected.
        with open(qp, "a") as f:
            f.write("\t\t\t\n%s\n" % ("x" * 200))
        check(len(tw.read_verify_requests(repo)) == 2,
              "pathological rows still do not raise")

        # --- the completion rule, which is the whole design ---
        with open(os.path.join(repo, tw.TSTATE_REL, "runs-box.ndjson"), "w") as f:
            f.write(json.dumps({"sha": shas[0], "date": "2026-01-01T00:00:00Z",
                                "tier": "native", "verdict": "GREEN"}) + "\n")

        class C: pass
        c = C(); c.path = repo
        c.remote_head = lambda: shas[2]
        due = tw.verify_request_due(c, "box", {})
        check(due is not None and due[0] == shas[1],
              "a request already judged at its tier is skipped; the next is due")
        check(tw.judged_tiers(c, "box", shas[0]) == {"native"},
              "completion is judged_tiers — no deletion, no acknowledgement")

        # A verdict at a DIFFERENT tier does not satisfy the request.
        with open(os.path.join(repo, tw.TSTATE_REL, "runs-box.ndjson"), "a") as f:
            f.write(json.dumps({"sha": shas[1], "date": "2026-01-02T00:00:00Z",
                                "tier": "native", "verdict": "GREEN"}) + "\n")
        due = tw.verify_request_due(c, "box", {})
        check(due is not None and due[0] == shas[1] and due[1] == "full",
              "a native verdict does NOT satisfy a request for full")

        # Satisfy it properly -> queue drains to nothing, file untouched.
        with open(os.path.join(repo, tw.TSTATE_REL, "runs-box.ndjson"), "a") as f:
            f.write(json.dumps({"sha": shas[1], "date": "2026-01-03T00:00:00Z",
                                "tier": "full", "verdict": "RED"}) + "\n")
        check(tw.verify_request_due(c, "box", {}) is None,
              "the queue drains with the file unchanged")
        check(len(tw.read_verify_requests(repo)) == 2,
              "draining did not delete the rows — replay is a no-op")

        # A RED verdict still satisfies: the request was for an ANSWER, not a
        # green one. Otherwise a red sha would be re-run forever.
        check("full" in tw.judged_tiers(c, "box", shas[1]),
              "a RED answer satisfies the request (it was asked, not hoped)")

        # Unreachable shas are skipped rather than checked out blindly.
        c.remote_head = lambda: shas[0]
        with open(qp, "a") as f:
            f.write("%s\tnative\tfrankT\tfuture\n" % shas[2])
        check(tw.verify_request_due(c, "box", {}) is None,
              "a sha this clone cannot reach is skipped, not attempted")

    print("\n%s (%d checks, %d failed)"
          % ("FAIL" if fails else "PASS", checks, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
