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
    src = (ROOT / "tools" / "progress.py").read_text(encoding="utf-8")
    i = src.index("def _warn_claim_is_local")
    body = src[i:i + 3000]
    assert '"push"' not in body, "the warning pushes; it must only report"
    assert "return" in body and "sys.exit" not in body, body[:200]
    return "it reports and never pushes or fails the claim"


CASES = [case_the_always_message_fires,
         case_a_live_claim_on_origin_is_reported,
         case_CONTROL_an_unclaimed_ticket_does_not_warn,
         case_CONTROL_your_own_claim_does_not_warn,
         case_it_never_pushes_and_never_fails]


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
