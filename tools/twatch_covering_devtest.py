#!/usr/bin/env python3
"""devtest: covering_runs() — the verdict query for an arbitrary commit.

Guards the distinction the query exists to make, which is easy to lose in a
refactor and silent when lost: an EXACT verdict (this sha was swept) is a
different and much stronger claim than a COVERING one (a later run's tree
contained this sha). Conflating them is how "sha X was green" gets written into
a ticket on evidence that does not say it.

Builds a throwaway git repo rather than reading the live archive: the real one
grows every few minutes, so an assertion about its contents is a test that
starts passing or failing on its own.
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
    with tempfile.TemporaryDirectory(prefix="twcov.") as repo:
        git(repo, "init", "-q", "-b", "master")
        git(repo, "config", "user.email", "t@example.invalid")
        git(repo, "config", "user.name", "devtest")
        shas = []
        for i in range(5):
            with open(os.path.join(repo, "f%d" % i), "w") as f:
                f.write("%d\n" % i)
            git(repo, "add", "-A")
            git(repo, "commit", "-qm", "c%d" % i)
            shas.append(git(repo, "rev-parse", "HEAD"))

        # A run archive that judges only c1 and c3 — the sparse ladder the real
        # watcher produces, where c0/c2/c4 are never swept individually.
        d = os.path.join(repo, tw.TSTATE_REL)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "runs-box.ndjson"), "w") as f:
            for sha, date, tier, verdict in [
                    (shas[1], "2026-01-01T00:00:00Z", "native", "GREEN"),
                    (shas[3], "2026-01-02T00:00:00Z", "native", "GREEN"),
                    (shas[3], "2026-01-02T01:00:00Z", "full",   "RED")]:
                f.write(json.dumps({"sha": sha, "date": date, "tier": tier,
                                    "verdict": verdict, "wall": 60}) + "\n")

        check(tw.archive_hosts(repo) == ["box"], "archive_hosts finds the host")
        check(len(list(tw.archive_rows(repo, "box"))) == 3,
              "archive_rows reads every row")
        check(list(tw.archive_rows(repo, "nosuch")) == [],
              "archive_rows on a missing host is empty, not an error")

        # c1 WAS swept: exact, and nothing later is claimed as exact.
        ex, cov = tw.covering_runs(repo, shas[1], "master")
        check([r["tier"] for r in ex] == ["native"], "c1 has its exact verdict")
        check(all(r["distance"] == 0 for r in ex), "an exact row is distance 0")
        check(sorted(r["tier"] for r in cov) == ["full", "native"],
              "c1 is also covered by the later c3 runs")
        check(all(r["distance"] == 2 for r in cov), "c3 is 2 commits past c1")

        # c2 was NEVER swept — the case the whole query exists for.
        ex, cov = tw.covering_runs(repo, shas[2], "master")
        check(ex == [], "c2 has NO exact verdict")
        check(len(cov) == 2 and all(r["distance"] == 1 for r in cov),
              "c2 is covered by c3's runs, one commit later")

        # c4 is past every run: covered by nothing. Must NOT inherit c3's green.
        ex, cov = tw.covering_runs(repo, shas[4], "master")
        check(ex == [] and cov == [],
              "c4 is uncovered — a later commit does not inherit an earlier verdict")

        # Direction matters: c0 is covered by everything, c3 by nothing before it.
        ex, cov = tw.covering_runs(repo, shas[0], "master")
        check(len(cov) == 3, "c0 is covered by all three later runs")

        # An unrelated branch must not count as covering: its tree never
        # contained the commit, and merge-base-free matching would say it did.
        git(repo, "checkout", "-q", "-b", "side", shas[0])
        with open(os.path.join(repo, "side"), "w") as f:
            f.write("x\n")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "side")
        side = git(repo, "rev-parse", "HEAD")
        with open(os.path.join(d, "runs-box.ndjson"), "a") as f:
            f.write(json.dumps({"sha": side, "date": "2026-01-03T00:00:00Z",
                                "tier": "full", "verdict": "GREEN",
                                "wall": 60}) + "\n")
        ex, cov = tw.covering_runs(repo, shas[2], "master")
        check(all(r["sha"] != side for r in cov),
              "a run on a sibling branch does not cover c2")

        # judged_tiers must still answer exactly as before, through the shared
        # reader — pin_verify_due depends on it.
        class C: pass
        c = C(); c.path = repo
        check(tw.judged_tiers(c, "box", shas[3]) == {"native", "full"},
              "judged_tiers still returns every tier for a sha")
        check(tw.judged_tiers(c, "box", shas[2]) == set(),
              "judged_tiers is empty for an unswept sha")

    print("\n%s (%d checks, %d failed)"
          % ("FAIL" if fails else "PASS", checks, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
