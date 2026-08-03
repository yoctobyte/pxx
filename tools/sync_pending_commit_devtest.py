#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for the resolve -> sync citation loop (progress.sh + sync.sh).

The bug this pins (bug-t-resolve-cites-a-sha-the-rebase-then-rewrites): the
documented loop was

    git commit                       -> abc123
    progress.sh resolve <slug> abc123        # sha written into the ticket
    tools/sync.sh                            # pull --rebase + push -> def456

and sync.sh REBASES. On this fleet the watcher daemon publishes tstate every
few minutes, so origin has almost always moved and the rebase rewrites every
local commit. The sha in the ticket then exists only in the author's local
reflog — the one place the other box cannot look. Four tickets in one session
cited commits nobody could resolve.

The fix under test: `resolve` may omit the sha (writing PENDING-COMMIT), and
sync.sh fills it in AFTER the push, when the sha is final.

Everything happens in a throwaway bare repo + two clones under /tmp; the real
repo is never touched. Run: python3 tools/sync_pending_commit_devtest.py
"""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

TOOLS = pathlib.Path(__file__).resolve().parent
PLACEHOLDER = "PENDING-COMMIT"
SLUG = "bug-scratch-widget-explodes"
TICKET = """---
summary: "the widget explodes"
type: bug
track: T
prio: 50
---

# The widget explodes

## Log
- 2026-08-03 — filed.
"""


def git(repo, *args, check=True):
    return subprocess.run(
        ["git", "-c", "user.name=devtest", "-c", "user.email=devtest@example",
         "-c", "commit.gpgsign=false", *args],
        cwd=repo, text=True, capture_output=True, check=check)


def build_scratch(tmp):
    """A bare origin, a dev clone carrying the tools, and a second clone that
    plays the watcher daemon pushing between our commit and our push."""
    origin = tmp / "origin.git"
    subprocess.run(["git", "init", "-q", "--bare", "--initial-branch=master",
                    str(origin)], check=True)

    dev = tmp / "dev"
    subprocess.run(["git", "clone", "-q", str(origin), str(dev)], check=True,
                   capture_output=True)
    (dev / "tools").mkdir()
    for name in ("sync.sh", "progress.sh", "progress.py"):
        shutil.copy2(TOOLS / name, dev / "tools" / name)
        (dev / "tools" / name).chmod(0o755)
    prog = dev / "devdocs" / "progress"
    (prog / "backlog").mkdir(parents=True)
    (prog / "done").mkdir(parents=True)
    (prog / f"backlog/{SLUG}.md").write_text(TICKET, encoding="utf-8")
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", "seed")
    git(dev, "push", "-q", "origin", "master")

    daemon = tmp / "daemon"
    subprocess.run(["git", "clone", "-q", str(origin), str(daemon)], check=True,
                   capture_output=True)
    return origin, dev, daemon


def daemon_publishes(daemon, n):
    """What actually forces the rebase in production: tstate landing on master
    between a dev box's commit and its push."""
    (daemon / f"tstate-{n}.json").write_text(f'{{"run": {n}}}\n', encoding="utf-8")
    git(daemon, "add", "-A")
    git(daemon, "commit", "-qm", f"tstate: run {n}")
    git(daemon, "push", "-q", "origin", "master")


def resolve_and_sync(dev, daemon, commit_arg):
    """One full loop; returns (pre-push local sha, ticket text on origin)."""
    argv = ["tools/progress.sh", "resolve", SLUG] + ([commit_arg] if commit_arg else [])
    subprocess.run(argv, cwd=dev, check=True, capture_output=True, text=True)
    git(dev, "add", "-A")
    git(dev, "commit", "-qm", f"fix(T): {SLUG}")
    local_sha = git(dev, "rev-parse", "--short=9", "HEAD").stdout.strip()

    daemon_publishes(daemon, 1)          # origin moves -> sync must rebase

    r = subprocess.run(["tools/sync.sh"], cwd=dev, text=True, capture_output=True)
    if r.returncode != 0:
        raise AssertionError(f"sync.sh failed: {r.stdout}{r.stderr}")
    landed = git(dev, "show", f"origin/master:devdocs/progress/done/{SLUG}.md").stdout
    return local_sha, landed


def cited_sha(text):
    m = re.search(r"commit ([0-9a-f]{7,40})", text)
    return m.group(1) if m else None


def on_origin(dev, sha):
    return git(dev, "merge-base", "--is-ancestor", sha, "origin/master",
               check=False).returncode == 0


def case_placeholder_is_filled_with_the_landed_sha(tmp):
    origin, dev, daemon = build_scratch(tmp)
    local_sha, landed = resolve_and_sync(dev, daemon, commit_arg=None)

    assert PLACEHOLDER not in landed, "placeholder survived onto origin"
    sha = cited_sha(landed)
    assert sha, f"no commit citation in the resolved ticket:\n{landed}"
    assert on_origin(dev, sha), f"cited {sha}, which is not on origin/master"
    assert not sha.startswith(local_sha[:7]), (
        f"cited the pre-rebase sha {local_sha} — the rebase should have moved it")
    return f"cited {sha} (pre-rebase was {local_sha})"


def case_explicit_sha_still_honoured(tmp):
    """Back-compat: `resolve <slug> <sha>` keeps writing exactly that sha, so
    a citation to a commit that landed EARLIER is not rewritten."""
    origin, dev, daemon = build_scratch(tmp)
    _, landed = resolve_and_sync(dev, daemon, commit_arg="deadbee")
    assert cited_sha(landed) == "deadbee", f"explicit sha not preserved:\n{landed}"
    return "explicit sha written verbatim"


def case_placeholder_filled_in_any_bucket(tmp):
    """A ticket resolved and filed onward in the same commit (done-followup/,
    for a fix that spawned a follow-up) must still get its sha. The first
    ticket ever resolved through this path did exactly that and the fill,
    scoped to done/ + decided/, walked straight past it."""
    origin, dev, daemon = build_scratch(tmp)
    subprocess.run(["tools/progress.sh", "resolve", SLUG], cwd=dev, check=True,
                   capture_output=True)
    followup = dev / "devdocs/progress/done-followup"
    followup.mkdir(parents=True, exist_ok=True)
    git(dev, "mv", f"devdocs/progress/done/{SLUG}.md",
        f"devdocs/progress/done-followup/{SLUG}.md")
    git(dev, "commit", "-qm", f"fix(T): {SLUG}")
    daemon_publishes(daemon, 1)
    r = subprocess.run(["tools/sync.sh"], cwd=dev, text=True, capture_output=True)
    assert r.returncode == 0, f"sync.sh failed: {r.stdout}{r.stderr}"
    landed = git(dev, "show",
                 f"origin/master:devdocs/progress/done-followup/{SLUG}.md").stdout
    assert PLACEHOLDER not in landed, "placeholder survived in done-followup/"
    sha = cited_sha(landed)
    assert sha and on_origin(dev, sha), f"cited {sha}, not on origin/master"
    return f"done-followup/ ticket cites {sha}"


def case_check_flags_a_dead_citation(tmp):
    """The audit that caught this by hand, made cheap."""
    origin, dev, daemon = build_scratch(tmp)
    resolve_and_sync(dev, daemon, commit_arg="deadbee")
    out = subprocess.run(["tools/progress.sh", "check", "--strict"], cwd=dev,
                         text=True, capture_output=True).stdout
    assert "WARN-DEAD-COMMIT" in out, f"check missed the dead citation:\n{out}"
    assert SLUG in out, f"check did not name the ticket:\n{out}"
    return "check --strict reports WARN-DEAD-COMMIT"


CASES = [
    case_placeholder_is_filled_with_the_landed_sha,
    case_explicit_sha_still_honoured,
    case_placeholder_filled_in_any_bucket,
    case_check_flags_a_dead_citation,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        with tempfile.TemporaryDirectory(prefix="sync-devtest-") as td:
            try:
                note = case(pathlib.Path(td))
            except AssertionError as e:
                print(f"  FAIL {name}: {e}")
                rc = 1
            else:
                print(f"  ok   {name} — {note}")
    print("resolve/sync citation loop OK" if rc == 0
          else "resolve/sync citation loop BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
