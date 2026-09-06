#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: `claim` says when the claim it just wrote cannot be seen.

`working/` is a status HINT, and a hint nobody can read is not one. Until a
claim lands on origin, `ready`, `next`, `git log` and every other check any
agent has will CORRECTLY report the ticket as unclaimed — nothing looks broken
from either end.

Measured 2026-08-30: four near-duplicate efforts in one evening, every one the
same shape — the work existed, the claim existed, and neither had left the
author's disk. A pull is a snapshot, and every check we have reads the snapshot.

TWO messages, and they are different jobs:

  * ALWAYS — "this claim is not on origin yet". Explains the state you are in.
  * CONDITIONALLY — "origin already has this in working/ under <someone>".
    PREVENTS the collision rather than explaining it afterwards.

The second is the one with teeth, so it carries the positive control: it must
NOT fire when origin's copy is unclaimed, and must NOT fire when the owner on
origin is you.

Run: python3 tools/progress_claim_visibility_devtest.py
"""
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROGRESS = pathlib.Path("devdocs/progress")


def _git(cwd, *a):
    return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True, text=True)


def _fixture(origin_owner=None, origin_folder="backlog"):
    """A clone whose origin/master holds one ticket, optionally already claimed."""
    d = pathlib.Path(tempfile.mkdtemp())
    bare, work = d / "origin.git", d / "work"
    _git(d, "init", "-q", "--bare", str(bare))
    _git(d, "clone", "-q", str(bare), str(work))
    _git(work, "config", "user.email", "t@t"); _git(work, "config", "user.name", "t")
    tdir = work / PROGRESS / origin_folder
    tdir.mkdir(parents=True)
    body = "---\nslug: demo\ntrack: T\nprio: 50\nstatus: %s\n" % origin_folder
    if origin_owner is not None:
        body += "owner: %s\n" % origin_owner
    body += '---\n\n# demo\n'
    (tdir / "demo.md").write_text(body)
    _git(work, "add", "-A"); _git(work, "commit", "-qm", "seed")
    _git(work, "push", "-q", "origin", "HEAD:master")
    _git(work, "fetch", "-q", "origin")
    return work


def _run_claim(work, owner="frankT"):
    """Run cmd_claim's warning against that tree. Returns stderr."""
    src = ROOT / "tools" / "progress.py"
    prog = work / "tools"
    prog.mkdir(exist_ok=True)
    (prog / "progress.py").write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
    code = (
        "import sys, pathlib\n"
        "sys.path.insert(0, %r)\n"
        "import progress as P\n"
        "P.ROOT = pathlib.Path(%r)\n"
        "P._warn_claim_is_local('demo', %r)\n"
        % (str(prog), str(work), owner))
    r = subprocess.run([sys.executable, "-c", code], cwd=work,
                       capture_output=True, text=True)
    return r.stderr


def case_the_always_message_fires():
    out = _run_claim(_fixture())
    assert "NOT on origin yet" in out, out
    assert "a pull is a snapshot" in out, out
    assert "tools/sync.sh" in out, out
    return "every claim says it is invisible until published"


def case_a_live_claim_on_origin_is_reported():
    out = _run_claim(_fixture(origin_owner="frankB", origin_folder="working"))
    assert "HEADS UP" in out, out
    assert "frankB" in out, out
    assert "do not decide it from the board" in out, out
    return "a ticket already held on origin warns before you duplicate the work"


def case_CONTROL_an_unclaimed_ticket_does_not_warn():
    # The guard with teeth needs a case it must NOT fire on, or it degrades into
    # a banner printed on every claim and stops meaning anything.
    out = _run_claim(_fixture())
    assert "HEADS UP" not in out, "the collision warning fired on an unclaimed ticket"
    return "no collision warning when origin's copy is not held"


def case_CONTROL_your_own_claim_does_not_warn():
    # Re-claiming your own parked work is the documented courtesy, not a
    # collision. Warning there would train the reader to ignore the message.
    out = _run_claim(_fixture(origin_owner="frankT", origin_folder="working"),
                     owner="frankT")
    assert "HEADS UP" not in out, "warned about your own claim"
    return "re-claiming your own held ticket is silent"


def case_it_never_pushes_and_never_fails():
    # Advisory by design: pushing on someone's behalf is a different decision,
    # and there are legitimate holds (a rebase under a running gate).
    # SLICE TO THE NEXT TOP-LEVEL `def`, NOT TO A FIXED CHARACTER COUNT.
    # This read `src[i:i + 3000]` until 2026-09-06, when the function's
    # docstring grew past the window and the `return` fell outside it: the case
    # went RED while the function behaved exactly as before, and reported that
    # the warning could fail the claim when it plainly could not. A fixed-width
    # window is a TRUNCATION instrument -- it does not error, it answers about
    # a prefix -- and it is the same animal as every other entry in this file.
    src = (ROOT / "tools" / "progress.py").read_text(encoding="utf-8")
    i = src.index("def _warn_claim_is_local")
    j = src.find("\ndef ", i + 1)
    body = src[i:j if j != -1 else len(src)]
    assert len(body) > 500, "the function body slice came out empty or truncated"
    assert '"push"' not in body, "the warning pushes; it must only report"
    assert "return" in body and "sys.exit" not in body, body[:200]
    return "it reports and never pushes or fails the claim (%d chars scanned)" % len(body)


def _land_on_origin_behind_your_back(work, owner="frankB", folder="working"):
    """Push a claim from a SECOND clone, leaving `work`'s origin/master stale.

    This is the shape of the 2026-09-06 collision exactly: two sessions, both
    of which claimed, both claims pushed. The second claimed from a tree pulled
    minutes earlier, so the guard read a ref that had never moved.
    """
    d = work.parent
    other = d / "other"
    if not other.exists():
        _git(d, "clone", "-q", str(d / "origin.git"), str(other))
        _git(other, "config", "user.email", "o@o")
        _git(other, "config", "user.name", "o")
    src = None
    for f in ("backlog", "working", "unfinished"):
        p = other / PROGRESS / f / "demo.md"
        if p.exists():
            src = p
            break
    assert src is not None, "fixture ticket not found in the second clone"
    dst = other / PROGRESS / folder / "demo.md"
    dst.parent.mkdir(parents=True, exist_ok=True)
    body = src.read_text().replace("status: backlog", "status: %s" % folder)
    if "owner:" not in body:
        body = body.replace("---\n\n# demo", "owner: %s\n---\n\n# demo" % owner, 1)
    dst.write_text(body)
    if dst != src:
        src.unlink()
    _git(other, "add", "-A")
    _git(other, "commit", "-qm", "someone else claims it")
    _git(other, "push", "-q", "origin", "HEAD:master")


def case_it_FETCHES_before_reading_origin():
    """THE CASE THAT ENCODES THE COLLISION. Without the fetch this is silent.

    `origin/master` is a LOCAL ref. A guard that reads it without fetching is a
    memory, not a measurement, and it goes quiet in exactly the situation it
    exists for -- the moment two sessions pick the same top-of-queue row within
    minutes of each other.
    """
    work = _fixture()
    _land_on_origin_behind_your_back(work, owner="frankB", folder="working")
    stale = _git(work, "rev-parse", "origin/master").stdout.strip()
    out = _run_claim(work)
    moved = _git(work, "rev-parse", "origin/master").stdout.strip()
    assert stale != moved, (
        "origin/master did not move: the claim check never fetched, so every "
        "assertion below would be about the world as of the last pull")
    assert "HEADS UP" in out and "frankB" in out, (
        "a claim that landed on origin AFTER the last pull was not reported:\n%s"
        % out)
    return "a claim pushed since your last pull is still caught"


def case_a_resolved_ticket_on_origin_is_reported():
    """A race lost by a wide enough margin has already left working/.

    The 2026-09-06 collision surfaced as an add/add conflict in done/: by the
    time the second session pushed, the first had already RESOLVED the ticket.
    A guard that only inspects working/ reports that row as free.
    """
    work = _fixture()
    _land_on_origin_behind_your_back(work, folder="done")
    out = _run_claim(work)
    assert "STOP" in out and "done/" in out, out
    assert "pick another row" in out, out
    return "a ticket resolved on origin stops the claim rather than colliding on push"


def case_CONTROL_a_backlog_ticket_is_not_reported_as_resolved():
    # The terminal-folder check needs a case it must NOT fire on, or it becomes
    # a banner on every claim and stops being read.
    out = _run_claim(_fixture())
    assert "STOP" not in out, "the resolved-ticket warning fired on a backlog row"
    return "no terminal-folder warning for an ordinary open ticket"


def case_a_failed_fetch_SAYS_SO_rather_than_answering_quietly():
    """A stale answer must not read like a clean one.

    This is the whole family: an instrument that lies by being correct about
    something else. With no network the check can still run and still be
    silent, and silence here means `nobody else has claimed it`.
    """
    work = _fixture()
    _git(work, "remote", "set-url", "origin",
         str(work.parent / "no-such-origin.git"))
    out = _run_claim(work)
    assert "COULD NOT FETCH" in out, (
        "the check could not reach origin and said nothing about it:\n%s" % out)
    assert "as of your" in out and "last pull" in out, out
    return "an unreachable origin is reported, not silently treated as clean"


CASES = [case_the_always_message_fires,
         case_a_live_claim_on_origin_is_reported,
         case_CONTROL_an_unclaimed_ticket_does_not_warn,
         case_CONTROL_your_own_claim_does_not_warn,
         case_it_never_pushes_and_never_fails,
         case_it_FETCHES_before_reading_origin,
         case_a_resolved_ticket_on_origin_is_reported,
         case_CONTROL_a_backlog_ticket_is_not_reported_as_resolved,
         case_a_failed_fetch_SAYS_SO_rather_than_answering_quietly]


def main():
    rc = 0
    for c in CASES:
        name = c.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = c()
        except Exception as e:
            print(f"  FAIL {name}: {type(e).__name__}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("claim visibility OK" if rc == 0 else "claim visibility BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
