#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a test job must not inherit the human's desktop session.

plexus was a headless watcher box until 2026-08-20, when borg's PSU failed and
it became the workstation. From that morning every job inherited a live desktop
session — 24 variables including DBUS_SESSION_BUS_ADDRESS, DISPLAY,
WAYLAND_DISPLAY, XAUTHORITY, XDG_RUNTIME_DIR (where at-spi autolaunches its
bus), and an unrelated third-party API key. `test/test_c_gtk_call.pas` hung
forever after gtk_init; three days of native tiers spent their full hour on it.

The first repair set NO_AT_BRIDGE=1 and GTK_A11Y=none. That unblocked the fleet
and did not fix the class: the next opportunistic client of a display, session
bus, keyring, portal or notification daemon hangs identically, and looks just as
mysterious because the repo will not have changed. A blocklist costs one outage
per symptom.

So the environment is an allowlist. The failure mode that replaces is the MIRROR
IMAGE — strip something a job needs and a green turns red with no visible cause
— so this guard pins both directions:

  * the session family is gone, and the allowlist has not quietly grown to
    re-admit it;
  * what a build-and-run actually needs is still there;
  * pass-through is by a job's own DEMONSTRATED reference, and is NOT triggered
    by xvfb-run/Xvfb/gui_shot. That was the first draft and it is backwards:
    those tools start a display of their own, so they are exactly the jobs that
    want the session stripped. Matching the tool name would have re-admitted the
    session bus to the three GTK jobs whose hang started this;
  * the documented escape hatch exists (a documented-but-absent hatch is its own
    defect);
  * the run SAYS what it dropped.

Run: tools/testmgr_job_env_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm", os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)

FAILS = []


def check(name, cond, detail=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  RED  %s" % name)
        FAILS.append("%s\n      %s" % (name, detail))


class FakeJob(object):
    def __init__(self, lines, sel="fake#0"):
        self.lines = lines
        self.sel = sel
        self.name = sel


def main():
    print("testmgr: a job must not inherit the desktop session")

    # Simulate a workstation session regardless of where this runs, so the
    # guard tests the RULE and not this box's current login state.
    poison = {
        "DISPLAY": ":0", "WAYLAND_DISPLAY": "wayland-0",
        "XAUTHORITY": "/run/user/1000/.mutter-Xwaylandauth",
        "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus",
        "XDG_RUNTIME_DIR": "/run/user/1000",
        "SSH_AUTH_SOCK": "/run/user/1000/keyring/ssh",
        "GNOME_SETUP_DISPLAY": ":1",
        "SOME_VENDOR_API_KEY": "sk-not-a-real-key",
    }
    needed = {"PATH": "/usr/bin:/bin", "HOME": "/home/x", "LANG": "C.UTF-8",
              "PXX_TRACK": "T", "TESTMGR_SOMETHING": "1", "LC_ALL": "C",
              "QEMU_LD_PREFIX": "/usr/aarch64-linux-gnu", "CC": "gcc"}
    saved = dict(os.environ)
    os.environ.update(poison)
    os.environ.update(needed)
    os.environ.pop("TESTMGR_INHERIT_ENV", None)
    try:
        env = tm.job_env()

        # --- the session must be gone --------------------------------------
        leaked = [v for v in tm.SESSION_ENV if v in env]
        check("no session/desktop variable survives", not leaked,
              "leaked: %s" % leaked)
        check("the at-spi autolaunch path (XDG_RUNTIME_DIR) is gone",
              "XDG_RUNTIME_DIR" not in env,
              "with no bus address at-spi AUTOLAUNCHES one and blocks there — "
              "the ticket measured that unsetting the bus ALONE still hangs")
        check("an unrelated vendor API key does not reach test subprocesses",
              "SOME_VENDOR_API_KEY" not in env,
              "every job in every tier would see it")

        # --- ...but what a build-and-run needs must remain ------------------
        for k in ("PATH", "HOME", "LANG", "CC"):
            check("keeps %s" % k, k in env, "stripping it breaks every job")
        check("keeps the PXX_ family", env.get("PXX_TRACK") == "T")
        check("keeps the TESTMGR_ family", "TESTMGR_SOMETHING" in env)
        check("keeps the LC_ family", "LC_ALL" in env)
        check("keeps the QEMU_ family (cross targets run through it)",
              "QEMU_LD_PREFIX" in env)

        # --- the a11y kill switches survive the rewrite ---------------------
        check("NO_AT_BRIDGE is set", env.get("NO_AT_BRIDGE") == "1",
              "the bus being absent is not enough on its own")
        check("GTK_A11Y is none", env.get("GTK_A11Y") == "none")

        # --- pass-through is by demonstrated need --------------------------
        plain = FakeJob(["./compiler/pascal26 test/x.pas /tmp/x", "/tmp/x"])
        check("an ordinary job does not get the session",
              not tm.job_needs_session(plain))

        xvfb = FakeJob(["./compiler/pascal26 test/test_c_gtk_call.pas /tmp/g",
                        "xvfb-run -a /tmp/g"])
        check("an xvfb-run job is NOT given the session",
              not tm.job_needs_session(xvfb),
              "xvfb-run starts its own display; passing the session through "
              "would re-admit the bus to the exact job that hung for 3 days")

        real = FakeJob(["test -n \"$DISPLAY\" && ./run_on_display"])
        check("a job naming $DISPLAY DOES get the session",
              tm.job_needs_session(real),
              "a real dependency must not be stripped silently")
        env2 = tm.job_env_for(real)
        check("...and that job actually receives it",
              env2.get("DISPLAY") == ":0", "got %r" % env2.get("DISPLAY"))
        env3 = tm.job_env_for(xvfb)
        check("...while the xvfb job still receives none",
              "DISPLAY" not in env3)

        # --- the escape hatch is real, not just documented ------------------
        os.environ["TESTMGR_INHERIT_ENV"] = "1"
        wide = tm.job_env()
        check("TESTMGR_INHERIT_ENV=1 restores inheritance",
              "DISPLAY" in wide and "SOME_VENDOR_API_KEY" in wide,
              "the docstring promises this hatch; a promised-but-absent hatch "
              "is the same defect as a promised-but-absent bisect")
        check("...and still forces the a11y switches off",
              wide.get("NO_AT_BRIDGE") == "1",
              "the hatch is for debugging the allowlist, not for re-hanging")
        os.environ.pop("TESTMGR_INHERIT_ENV")

        # --- it must announce itself ---------------------------------------
        note = tm.env_strip_report([plain, xvfb])
        check("the run reports what it stripped", "ALLOWLIST" in note, note)
        check("the report names variables, not a count alone",
              "DISPLAY" in note, note)
        note2 = tm.env_strip_report([real])
        check("the report names the jobs that kept the session",
              "fake#0" in note2 and "keep the session" in note2, note2)
    finally:
        os.environ.clear()
        os.environ.update(saved)

    if FAILS:
        print("\ntestmgr_job_env_devtest: %d RED" % len(FAILS))
        for f in FAILS:
            print("  - %s" % f)
        return 1
    print("testmgr_job_env_devtest: all green")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(fail_detail(e))
        sys.exit(1)
