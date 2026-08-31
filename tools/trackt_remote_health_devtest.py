#!/usr/bin/env python3
"""`trackt health` on a box that is not the watcher host.

Before 2026-08-31 this could only ever say DOWN: `daemon_pid` falls back to
scanning /proc, and a watcher on another host has no entry in this box's
process table, so the match cannot occur. Since the watcher moved to seven on
2026-08-29 that made DOWN permanent on every dev box — and CLAUDE.md names
`trackt.py health` reporting DOWN as PROOF Track T is down, whose stated
consequence is to run your lane's FULL gate. A check that could only return one
answer was licensing the ~10-minute widening the no-full-suite hook exists to
prevent, through the documented command rather than around it.

THE POSITIVE CONTROL IS THE POINT. A guard that cannot fail is not a guard, so
the case this must REJECT is asserted first and separately: a stale archive
with no local daemon MUST still come back DOWN. Without that, "it says REMOTE
now" would be a check that had merely swapped which single answer it gives.
"""
import calendar
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import twatch                                              # noqa: E402
import trackt                                              # noqa: E402


def stamp(offset_secs):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ",
                         time.gmtime(time.time() - offset_secs))


def make_repo(tmp, rows):
    """A fake checkout carrying only a published tstate archive."""
    tdir = os.path.join(tmp, twatch.TSTATE_REL)
    os.makedirs(tdir, exist_ok=True)
    for host, entries in rows.items():
        with open(os.path.join(tdir, "runs-%s.ndjson" % host), "w") as f:
            for e in entries:
                f.write(json.dumps(e) + "\n")
    return tmp


def row(age, sha="abc123def456", tier="full", verdict="GREEN"):
    return {"date": stamp(age), "sha": sha, "tier": tier, "verdict": verdict}


FAILS = []


def check(name, cond, detail=""):
    print("  %-4s %s%s" % ("ok" if cond else "FAIL", name,
                           "" if cond else "  <- " + detail))
    if not cond:
        FAILS.append(name)


def main():
    print("the case it MUST reject — without this the check is not a check")
    with tempfile.TemporaryDirectory() as tmp:
        # 3x REMOTE_STALE_SECS: unambiguously stale, no boundary argument.
        make_repo(tmp, {"seven": [row(trackt.REMOTE_STALE_SECS * 3)]})
        v, rc, why = trackt.no_local_daemon(tmp)
        check("a STALE archive and no local daemon is still DOWN", v == "DOWN",
              "got %s" % v)
        check("...and exits 2, which is what the docs key the exception on",
              rc == 2, "got %d" % rc)
        check("...and the reason names the age, not just 'no daemon'",
              any("old" in r for r in why), why)

    print("no archive at all is DOWN too — absence of evidence is not a green")
    with tempfile.TemporaryDirectory() as tmp:
        make_repo(tmp, {})
        v, rc, _ = trackt.no_local_daemon(tmp)
        check("empty tstate dir -> DOWN", v == "DOWN" and rc == 2, "got %s/%d" % (v, rc))

    print("and only then, the case it must ACCEPT")
    with tempfile.TemporaryDirectory() as tmp:
        make_repo(tmp, {"seven": [row(600, tier="native", verdict="RED")]})
        v, rc, why = trackt.no_local_daemon(tmp)
        check("a FRESH archive and no local daemon is REMOTE, not DOWN",
              v == "REMOTE", "got %s" % v)
        check("...and exits 0, so it cannot arm the full-gate exception",
              rc == 0, "got %d" % rc)
        check("...and a RED verdict in the newest row does not make it DOWN",
              v == "REMOTE",
              "the question is whether T is SWEEPING, not whether it is green")
        check("...and it names the publishing host, so the reader can chase it",
              any("seven" in r for r in why), why)

    print("the newest row wins across hosts, not the newest file")
    with tempfile.TemporaryDirectory() as tmp:
        make_repo(tmp, {"seven": [row(trackt.REMOTE_STALE_SECS * 3)],
                        "plexus": [row(300, sha="fedcba987654")]})
        v, _, why = trackt.no_local_daemon(tmp)
        check("a fresh row on ANY host answers the question", v == "REMOTE",
              "got %s" % v)
        check("...and it is the fresh row that gets quoted",
              any("fedcba987654" in r for r in why), why)

    print("boundary: the threshold is measured, so it must actually bind")
    with tempfile.TemporaryDirectory() as tmp:
        make_repo(tmp, {"seven": [row(trackt.REMOTE_STALE_SECS - 120)]})
        v, _, _ = trackt.no_local_daemon(tmp)
        check("just inside the window -> REMOTE", v == "REMOTE", "got %s" % v)
    with tempfile.TemporaryDirectory() as tmp:
        make_repo(tmp, {"seven": [row(trackt.REMOTE_STALE_SECS + 120)]})
        v, _, _ = trackt.no_local_daemon(tmp)
        check("just outside it -> DOWN", v == "DOWN", "got %s" % v)

    print()
    if FAILS:
        print("FAILED %d check(s): %s" % (len(FAILS), ", ".join(FAILS)))
        return 1
    print("all trackt remote-health guards green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
