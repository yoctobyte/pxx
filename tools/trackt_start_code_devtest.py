#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the daemon must never be started from the sha it was last testing.

bug-t-daemon-restarts-into-the-tested-shas-code.

`daemon_script()` deliberately runs the CLONE's copy of twatch.py, so that
"restart to pick up a fix" means "pull, then restart". But the clone is
DETACHED at the sha under test for most of every cycle — and always after a
crash, which is precisely when someone restarts it. Launching then executes
that sha's twatch.py: an arbitrary old version of the watcher's own code.

Measured 2026-08-04. A crash left the clone detached at `ac03897df`, so
`trackt up` relaunched the code that had just crashed; it re-created the file
it crashed on and died the same way. Two identical outages, and the log made it
worse — the traceback rendered the CURRENT file's source lines against the OLD
file's line numbers, so the fix appeared to be in place.

Scratch git repos only.
Run: python3 tools/trackt_start_code_devtest.py
"""
import pathlib
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import trackt  # noqa: E402


def git(repo, *args, check=True):
    return subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=devtest",
         "-c", "user.email=d@e", "-c", "commit.gpgsign=false", *args],
        capture_output=True, text=True, check=check)


def scratch_clone():
    """An origin with two commits, and a clone detached on the OLD one — the
    state a crashed watcher leaves behind."""
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="trackt-start-"))
    origin = tmp / "origin"
    subprocess.run(["git", "init", "-q", "--initial-branch=master", str(origin)],
                   check=True)
    (origin / "tools").mkdir()
    (origin / "tools" / "twatch.py").write_text("OLD\n")
    git(origin, "add", "-A")
    git(origin, "commit", "-qm", "old")
    old = git(origin, "rev-parse", "HEAD").stdout.strip()
    (origin / "tools" / "twatch.py").write_text("FIXED\n")
    git(origin, "add", "-A")
    git(origin, "commit", "-qm", "the fix")

    clone = tmp / "clone"
    subprocess.run(["git", "clone", "-q", str(origin), str(clone)], check=True,
                   capture_output=True)
    git(clone, "checkout", "-q", "--detach", old)     # crashed mid-test
    return clone, old


def case_detached_clone_is_returned_to_the_branch():
    clone, old = scratch_clone()
    assert (clone / "tools" / "twatch.py").read_text() == "OLD\n", "test setup"
    assert trackt.ensure_clone_on_branch(str(clone)) is True
    assert (clone / "tools" / "twatch.py").read_text() == "FIXED\n", \
        "the daemon would have been launched from the tested sha's code"
    head = git(clone, "symbolic-ref", "-q", "HEAD", check=False).stdout.strip()
    assert head.endswith("master"), f"still detached: {head!r}"
    return "detached at an old sha -> back on master, current code"


def case_clone_already_current_is_left_alone():
    clone, _ = scratch_clone()
    git(clone, "checkout", "-q", "master")
    git(clone, "pull", "-q", "--ff-only", "origin", "master", check=False)
    before = git(clone, "rev-parse", "HEAD").stdout
    assert trackt.ensure_clone_on_branch(str(clone)) is True
    assert git(clone, "rev-parse", "HEAD").stdout == before
    return "already on master -> unchanged"


def case_dirty_clone_refuses_rather_than_starting_something_arbitrary():
    """A checkout that cannot be made current must stop the start, not be
    papered over — the daemon refuses dirty clones for the same reason."""
    clone, _ = scratch_clone()
    (clone / "tools" / "twatch.py").write_text("LOCAL EDIT\n")
    assert trackt.ensure_clone_on_branch(str(clone)) is False, \
        "a clone that cannot check out its branch was allowed to start"
    return "dirty clone -> False, caller refuses"


def with_unit_file(text):
    """Point trackt.unit_path() at a scratch unit file holding `text`."""
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="trackt-unit-"))
    unit = tmp / "trackt-watcher.service"
    unit.write_text(text)
    trackt.unit_path = lambda: str(unit)          # noqa: E731 - devtest seam
    return unit


UNIT = ("[Service]\nExecStart=/usr/bin/python3 %s/tools/twatch.py "
        "--clone %s\nRestart=on-failure\n")


def case_installed_unit_is_used_instead_of_a_bare_process():
    """A start on a supervised box must go through systemd.

    Popen-ing the daemon directly trades Restart=on-failure and the
    zero-length-twatch.py ExecStartPre for a process nothing brings back — the
    exact state a power cut left on 2026-08-20, arrived at by default.
    """
    orig = trackt.unit_path
    try:
        with_unit_file(UNIT % ("/home/x/trackt-watch", "/home/x/trackt-watch"))
        got = trackt.supervised_unit("/home/x/trackt-watch")
        assert got == trackt.UNIT_NAME, "unit not recognised: %r" % got
    finally:
        trackt.unit_path = orig
    return "clone with a unit -> systemd start"


def case_another_clones_unit_is_not_borrowed():
    """A unit names ONE clone; a second clone on the box must not ride it."""
    orig = trackt.unit_path
    try:
        with_unit_file(UNIT % ("/home/x/trackt-watch", "/home/x/trackt-watch"))
        assert trackt.supervised_unit("/home/x/other-clone") is None, \
            "started a different clone through somebody else's unit"
        assert trackt.supervised_unit("/home/x/trackt-watch2") is None, \
            "prefix match: 'trackt-watch' accepted for 'trackt-watch2'"
    finally:
        trackt.unit_path = orig
    return "foreign / prefix-alike clone -> direct launch"


def case_no_unit_installed_still_starts():
    """The common unsupervised box keeps working exactly as before."""
    orig = trackt.unit_path
    try:
        trackt.unit_path = lambda: "/nonexistent/trackt-watcher.service"
        assert trackt.supervised_unit("/home/x/trackt-watch") is None
    finally:
        trackt.unit_path = orig
    return "no unit -> direct launch, unchanged"


CASES = [
    case_detached_clone_is_returned_to_the_branch,
    case_clone_already_current_is_left_alone,
    case_dirty_clone_refuses_rather_than_starting_something_arbitrary,
    case_installed_unit_is_used_instead_of_a_bare_process,
    case_another_clones_unit_is_not_borrowed,
    case_no_unit_installed_still_starts,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = case()
        except AssertionError as e:
            print(f"  FAIL {name}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("daemon start-code discipline OK" if rc == 0
          else "daemon start-code discipline BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
