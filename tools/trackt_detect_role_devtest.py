#!/usr/bin/env python3
"""Devtest for trackt's box-role detection and the non-interactive wizard.

The bug this guards: `configure_profile` used to write 'dedicated' whenever
there was no TTY, so a Pi provisioned headless over ssh — the most likely way
one is ever set up — enrolled itself as a full-matrix fuzzing box with all
cores and idle fuzzing on
(feature-t-trackt-setup-autodetect-box-role).

Pure temp dirs and monkeypatched probes: no clone, no daemon, no network.
"""
import json
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import trackt  # noqa: E402

fails = []


def check(name, cond, got=""):
    print(("  ok   " if cond else "  FAIL ") + name +
          (("  got: %s" % got) if not cond and got else ""))
    if not cond:
        fails.append(name)


def with_box(machine, desktop, model=None):
    """Pretend to be a particular machine for one detect_role() call."""
    real_machine, real_desktop = trackt.platform.machine, trackt._has_desktop_session
    trackt.platform.machine = lambda: machine
    trackt._has_desktop_session = lambda: desktop
    try:
        return trackt.detect_role
    finally:
        pass  # caller restores via restore()


def restore(real_machine, real_desktop):
    trackt.platform.machine = real_machine
    trackt._has_desktop_session = real_desktop


def main():
    real_machine = trackt.platform.machine
    real_desktop = trackt._has_desktop_session
    try:
        # --- role detection ------------------------------------------------
        with_box("aarch64", False)
        role, why = trackt.detect_role(4, 8192)
        check("arm64 Pi, headless -> native-oracle", role == "native-oracle", role)
        check("  ...and says why", any("QEMU" in r for r in why), why)

        with_box("aarch64", True)
        role, _ = trackt.detect_role(16, 65536)
        check("a BIG arm box is still an oracle (arch beats size)",
              trackt.detect_role(16, 65536)[0] == "native-oracle", role)

        with_box("x86_64", True)
        role, why = trackt.detect_role(8, 16384)
        check("x86_64 with a desktop session -> limited", role == "limited", role)
        check("  ...and says why", any("graphical" in r for r in why), why)

        with_box("x86_64", False)
        role, _ = trackt.detect_role(12, 61440)
        check("headless many-core x86_64 -> dedicated", role == "dedicated", role)

        with_box("x86_64", False)
        role, _ = trackt.detect_role(2, 2048)
        check("headless but tiny x86_64 -> limited", role == "limited", role)

        # --- the non-interactive path, which is where the bug lived --------
        trackt.ISATTY = False
        for machine, desktop, want in (("aarch64", False, "native-oracle"),
                                       ("x86_64", False, "dedicated"),
                                       ("x86_64", True, "limited")):
            with_box(machine, desktop)
            d = pathlib.Path(tempfile.mkdtemp(prefix="trackt-role-"))
            trackt.configure_profile(str(d))
            conf = json.loads((d / trackt.twatch.CONF_NAME).read_text())
            want_conf = {k: v for k, v in trackt.PROFILES[want].items()
                         if not k.startswith("_")}
            check("no TTY, %s%s -> %s profile written"
                  % (machine, " +desktop" if desktop else "", want),
                  all(conf.get(k) == v for k, v in want_conf.items()), conf)
            if want != "dedicated":
                check("  ...and it is NOT the old blanket dedicated",
                      conf.get("tier") == "native" or conf.get("idle_fuzz") is False,
                      conf)

        # --- the interactive proposal: Enter accepts, a number overrides ----
        trackt.ISATTY = True
        real_input = __builtins__["input"] if isinstance(__builtins__, dict) \
            else __builtins__.input
        for typed, want in (("", "native-oracle"), ("2", "limited")):
            with_box("aarch64", False)
            d = pathlib.Path(tempfile.mkdtemp(prefix="trackt-role-"))
            if isinstance(__builtins__, dict):
                __builtins__["input"] = lambda _p="": typed
            else:
                __builtins__.input = lambda _p="": typed
            try:
                trackt.configure_profile(str(d))
            finally:
                if isinstance(__builtins__, dict):
                    __builtins__["input"] = real_input
                else:
                    __builtins__.input = real_input
            conf = json.loads((d / trackt.twatch.CONF_NAME).read_text())
            want_conf = {k: v for k, v in trackt.PROFILES[want].items()
                         if not k.startswith("_")}
            check("interactive %s -> %s"
                  % ("Enter" if not typed else "typed " + typed, want),
                  all(conf.get(k) == v for k, v in want_conf.items()), conf)
        trackt.ISATTY = False

        # --- RAM is actually read (it silently was not: twatch.meminfo() ----
        # does not exist, so the wizard saw 0 MB and the memory cap never fired)
        check("this box's RAM is detected, not 0", trackt.total_ram_mb() > 0,
              trackt.total_ram_mb())
        d = pathlib.Path(tempfile.mkdtemp(prefix="trackt-role-"))
        trackt._write_profile(str(d / "c.json"), "restricted", 8, 8192)
        conf = json.loads((d / "c.json").read_text())
        check("restricted profile's memory cap is written",
              conf.get("max_mem_mb") == 4096, conf)

        # an existing conf is never overwritten
        d = pathlib.Path(tempfile.mkdtemp(prefix="trackt-role-"))
        (d / trackt.twatch.CONF_NAME).write_text('{"autoticket": true}\n')
        trackt.configure_profile(str(d))
        check("existing twatch.conf left alone",
              json.loads((d / trackt.twatch.CONF_NAME).read_text())
              == {"autoticket": True})
    finally:
        restore(real_machine, real_desktop)

    print()
    print("FAILED: " + ", ".join(fails) if fails else "all role-detection cases pass")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
