#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a missing qemu emulator SKIPS its jobs, it does not RED them.

tools/run_target.sh `need`s the matching qemu-user binary and exits 2 when it is
absent. Without this guard, a box that never ran tools/install_qemu.sh turns
every job of every cross target red, and nothing in the report distinguishes
that from a defect in the tree.

The bill has been paid once already. rejected/regression-cascade-154d1aa3fba6:
ten of eighteen "newly red" jobs on a fresh watcher box were a missing i386
loader and an absent cross sysroot -- auto-filed at prio 70 against twelve
innocent commits, and it cost three agents a triage cycle before anyone read
the job logs. A red is strictly worse than a skip here for the reason the corpus
guard already gives: it masks a future real regression in that job permanently,
while every later run reads it as STILL-RED rather than as coverage loss.

The guards, and the two that are about NOT skipping:

  1. an absent emulator skips the jobs that need it.
  2. the reason names tools/install_qemu.sh -- a skip that does not say how to
     un-skip itself is how a coverage hole becomes permanent.
  3. jobs for a DIFFERENT arch are untouched. One missing emulator must not
     take the matrix with it.
  4. i386 is never skipped, however absent qemu-i386 is: run_target.sh tries
     the NATIVE path first and only falls back, so on a kernel with ia32
     emulation the job runs fine. Same asymmetry host_cpu_flags() argues for --
     when in doubt, RUN the job.
  5. x86_64 likewise: it execs directly and touches no emulator at all.
  6. a job already skipped for another reason keeps its FIRST reason, which is
     the actionable one.

Run: python3 tools/testmgr_host_tool_skip_devtest.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr as tm  # noqa: E402

fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-56s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def main():
    print("1. the arch -> emulator map matches run_target.sh's unconditional needs")
    mapped = dict(tm.HOST_TOOLS)
    check(mapped == {"aarch64": "qemu-aarch64", "arm32": "qemu-arm",
                     "riscv32": "qemu-riscv32", "riscv64": "qemu-riscv64",
                     "xtensa": "qemu-xtensa"},
          "five arches, and only the ones run_target.sh `need`s", str(sorted(mapped)))
    check("i386" not in mapped, "i386 is NOT in the map (native path first)")
    check("x86_64" not in mapped, "x86_64 is NOT in the map (no emulator at all)")

    print("2. the recipe regex finds the arch run_target.sh was handed")
    f = tm.RUN_TARGET_RE.findall
    check(f("tools/run_target.sh xtensa /tmp/x") == ["xtensa"], "plain invocation")
    check(f('"$(tools/run_target.sh aarch64 /tmp/a)"') == ["aarch64"],
          "inside a command substitution")
    check(f("printf 'x' | tools/run_target.sh riscv32 /tmp/r") == ["riscv32"],
          "downstream of a pipe")
    check(f("./compiler/pascal26 test/hello.pas /tmp/h") == [],
          "a job that runs nothing foreign matches nothing")

    print("3. missing_emulators() reports absence, not presence")
    real = tm.shutil.which
    try:
        tm.shutil.which = lambda exe: None if exe == "qemu-xtensa" else "/usr/bin/" + exe
        absent = tm.missing_emulators()
        check(absent == {"xtensa": "qemu-xtensa"},
              "exactly the one that is gone", str(absent))
        tm.shutil.which = lambda exe: "/usr/bin/" + exe
        check(tm.missing_emulators() == {}, "a fully provisioned box skips nothing")
        tm.shutil.which = lambda exe: None
        check(len(tm.missing_emulators()) == 5,
              "a box with no qemu at all reports all five")
    finally:
        tm.shutil.which = real

    print("4. the skip is APPLIED to the right jobs and only those")

    class J:                      # enough of Job for apply_host_tool_skips
        def __init__(self, name, lines, status="queued", reason=""):
            self.name, self.lines = name, lines
            self.status, self.skip_reason = status, reason

    def fresh():
        return [
            J("xtensa#01", ["./c --target=xtensa test/hello.pas /tmp/h",
                            "tools/run_target.sh xtensa /tmp/h"]),
            J("aarch64#01", ["tools/run_target.sh aarch64 /tmp/a"]),
            J("i386#01", ["tools/run_target.sh i386 /tmp/i"]),
            J("core#01", ["./c test/hello.pas /tmp/h", "/tmp/h"]),
            J("x86_64#01", ["tools/run_target.sh x86_64 /tmp/n"]),
            J("corpus#01", ["tools/run_target.sh xtensa /tmp/x"],
              status="skip", reason="corpus root absent: run install_lib_candidates.sh"),
        ]

    js = fresh()
    n = tm.apply_host_tool_skips(js, {"xtensa": "qemu-xtensa"})
    by = {j.name: j for j in js}
    check(n == 1, "exactly one job skipped", "n=%d" % n)
    check(by["xtensa#01"].status == "skip", "the xtensa job is skipped")
    check("tools/install_qemu.sh" in by["xtensa#01"].skip_reason,
          "and its reason names the command that un-skips it")
    check("qemu-xtensa" in by["xtensa#01"].skip_reason,
          "and names the missing binary")
    check(by["aarch64#01"].status != "skip",
          "a job for a DIFFERENT arch is untouched")
    check(by["i386#01"].status != "skip",
          "an i386 job is never skipped by this guard")
    check(by["core#01"].status != "skip",
          "a job that runs nothing foreign is untouched")
    check(by["x86_64#01"].status != "skip",
          "run_target.sh x86_64 execs natively and is never skipped")
    check(by["corpus#01"].skip_reason.startswith("corpus root absent"),
          "an already-skipped job KEEPS its first, actionable reason")

    js = fresh()
    check(tm.apply_host_tool_skips(js, {}) == 0
          and not any(j.status == "skip" for j in js if j.name != "corpus#01"),
          "no absent emulator -> nothing is touched at all")

    print("5. this box, measured (not asserted -- it is the environment)")
    here = tm.missing_emulators()
    print("       missing here: %s" % (sorted(here.values()) or "none"))

    print("\n  %d guard(s), %d FAIL" % (20, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
