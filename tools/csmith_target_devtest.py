#!/usr/bin/env python3
"""Guards for tools/csmith_fuzz.py --target (cross-compile + run under qemu).

Every branch below is exercised with a stubbed run(), because the real thing
needs csmith, a cross toolchain and qemu, and the interesting cases are the ones
that are HARD to produce on demand (a cross gcc that is absent, a checksum that
differs for a legitimate reason).

The thing being guarded is not "does --target build". It is that a cross run
cannot report a difference it did not measure:

  * a native x86-64 gcc and an ILP32 target disagree over `long` widths for
    reasons that are not miscompiles, so the vs-gcc comparison must be DROPPED
    for a target with no data-model-matching oracle, not run anyway;
  * a ratio against a native oracle measures qemu, so PXX_SLOW must not fire
    there either;
  * and the run must SAY it dropped them. A silent drop turns "we did not check"
    into "we checked and it agreed", which is the exact defect class this
    harness keeps finding in itself.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import csmith_fuzz as C  # noqa: E402

fails = []


def check(cond, what):
    print("  %s %s" % ("ok  " if cond else "FAIL", what))
    if not cond:
        fails.append(what)


class Stub:
    """A scripted run(): answers by looking at argv, and records every call."""

    def __init__(self, pxx_sum="CS 1", oracle_sum="CS 1", pxx_sec=0.1,
                 oracle_sec=0.1, pxx_rc=0, per_opt=None):
        self.calls = []
        self.pxx_sum, self.oracle_sum = pxx_sum, oracle_sum
        self.pxx_sec, self.oracle_sec = pxx_sec, oracle_sec
        self.pxx_rc, self.per_opt = pxx_rc, per_opt or {}
        self.limits = []
        self.oracle_run = None

    def __call__(self, cmd, timeout, cwd=None):
        cmd = [str(c) for c in cmd]
        self.calls.append((cmd, timeout))
        if cmd[0] == "csmith":
            pathlib.Path(cmd[cmd.index("--output") + 1]).write_text("int main(){}\n")
            return 0, "", 0.0
        if "-o" in cmd:
            return 0, "", 0.0                      # any compile: gcc, oracle, probe
        if cmd[0].endswith("pascal26"):
            return 0, "", 0.0                      # pxx compiling (output is positional)
        if cmd[-1].endswith("probe.bin"):
            return 42, "", 0.0                     # the probe's own run
        if cmd[-1].endswith("/g"):
            return 0, "checksum = %s\n" % self.oracle_sum, self.oracle_sec
        if cmd[-1].endswith("/o"):
            self.oracle_run = cmd
            return 0, "checksum = %s\n" % self.oracle_sum, self.oracle_sec
        # running a pxx binary, possibly through the runner
        self.limits.append(timeout)
        opt = cmd[-1][-1]
        if opt in self.per_opt:
            s, sec = self.per_opt[opt]
            return (0, "checksum = %s\n" % s, sec) if s is not None else (None, "<timeout>", sec)
        if self.pxx_rc is None:
            return None, "<timeout>", timeout
        return self.pxx_rc, "checksum = %s\n" % self.pxx_sum, self.pxx_sec


def fuzz(tmp, target, oracle_cc, **kw):
    stub = Stub(**kw)
    old = C.run
    C.run = stub
    try:
        cfg = C.Cfg(pathlib.Path("/x/compiler/pascal26"), pathlib.Path("/inc"),
                    ["0", "2"], 15, [], target, oracle_cc)
        return cfg, stub, C.fuzz_one(1, cfg, tmp)
    finally:
        C.run = old


import tempfile  # noqa: E402
tmp = pathlib.Path(tempfile.mkdtemp(prefix="csmith-devtest-"))

print("the default target is untouched by any of this")
cfg = C.Cfg(pathlib.Path("/x/pascal26"), pathlib.Path("/inc"), ["0"], 15, [], "x86_64", ["gcc"])
check(cfg.runner == [], "x86_64 runs bare — no run_target.sh in the timed path")
check("--target=x86_64" not in cfg.pxx_cmd("0", "t.c", "t"),
      "...and pxx is invoked without a --target it never needed")
check(cfg.emulated is False, "x86_64 is not emulated")

print("a cross target reaches BOTH sides: the compiler and the runner")
cfg = C.Cfg(pathlib.Path("/x/pascal26"), pathlib.Path("/inc"), ["0"], 15, [], "aarch64", None)
check("--target=aarch64" in cfg.pxx_cmd("0", "t.c", "t"), "pxx gets --target=aarch64")
check(cfg.runner[-1] == "aarch64" and cfg.runner[0].endswith("run_target.sh"),
      "the emitted binary is run through tools/run_target.sh aarch64")
check(cfg.emulated is True, "aarch64 is emulated (its budgets are widened)")
check(C.Cfg(pathlib.Path("/x"), pathlib.Path("/i"), ["0"], 15, [], "i386", None).emulated is False,
      "i386 is NOT emulated — an x86-64 kernel execs it natively")

print("no oracle: the difference we cannot interpret is not reported as a defect")
cfg, stub, f = fuzz(tmp, "aarch64", None, pxx_sum="CS 32bit", oracle_sum="CS 64bit")
check(f is None,
      "a pxx/native-gcc checksum difference on a cross target is NOT MISCOMPILE_VS_GCC")
check(any(c[0][0] == "gcc" for c in stub.calls),
      "...but the native gcc still ran, as the validity filter it also is")
cfg, stub, f = fuzz(tmp, "aarch64", None, per_opt={"0": ("A", 0.1), "2": ("B", 0.1)})
check(f is not None and f.bucket == "MISCOMPILE_OPT",
      "pxx disagreeing with ITSELF is still a finding — one target, no data model in it")

print("no oracle: no ratio, therefore no PXX_SLOW and no scaled budget")
cfg, stub, f = fuzz(tmp, "aarch64", None, pxx_sec=99.0, oracle_sec=0.5)
check(f is None, "200x the NATIVE oracle is not PXX_SLOW — that ratio measures qemu")
check(stub.limits and stub.limits[0] == 15 * C.EMU_TIMEOUT_FACTOR,
      "the budget is the flat --timeout widened for emulation (%ds)" % (15 * C.EMU_TIMEOUT_FACTOR))
cfg, stub, f = fuzz(tmp, "aarch64", None, pxx_rc=None)
check(f is not None and f.bucket == "PXX_TIMEOUT", "a real hang is still PXX_TIMEOUT")
check("FLAT budget" in f.detail,
      "...and its detail says the budget was flat, so the reader knows how far to trust it")

print("with a matching oracle, everything comes back — and it runs the same way we do")
oc = ["aarch64-linux-gnu-gcc", "-static"]
cfg, stub, f = fuzz(tmp, "aarch64", oc, pxx_sum="CS 1", oracle_sum="CS 2")
check(f is not None and f.bucket == "MISCOMPILE_VS_GCC",
      "a mismatch against a data-model-matching oracle IS a miscompile")
check(stub.oracle_run and stub.oracle_run[0].endswith("run_target.sh"),
      "the oracle binary is run through run_target.sh too — both sides emulated")
cfg, stub, f = fuzz(tmp, "aarch64", oc, pxx_sec=9.0, oracle_sec=1.0)
check(f is not None and f.bucket == "PXX_SLOW",
      "9x an EMULATED oracle is PXX_SLOW — that ratio is qemu over qemu, so it means something")
# A 1s oracle scales to 20s, under the 180s emulated floor, so the floor wins —
# which is the point of having one. Give it an oracle slow enough to exceed the
# floor and the scaling must take over, or the seed-90044 protection is dead
# under emulation and nothing would have said so.
cfg, stub, f = fuzz(tmp, "aarch64", oc, pxx_sec=1.0, oracle_sec=20.0)
check(stub.limits and stub.limits[0] == C.TIMEOUT_FACTOR * 20.0,
      "a slow oracle scales the budget past the emulated floor (%ds)"
      % (C.TIMEOUT_FACTOR * 20))
check(15 * C.EMU_TIMEOUT_FACTOR > C.TIMEOUT_FACTOR * 1.0,
      "...and below that, the floor is what protects a fast oracle from a tight budget")

print("the probe answers honestly, and says so either way")
cc, note = C.probe_oracle("aarch64", tmp)
check(cc is None, "no aarch64 cross gcc on this box, so no oracle is claimed")
check("NO ORACLE" in note and "LP64" in note and "NOT CHECKED" in note,
      "...and the note names the target's data model and what went unchecked")
check("not installed" in note, "...and why (the compiler is absent, not broken)")
cc, note = C.probe_oracle("x86_64", tmp)
check(cc == ["gcc"] and "matches the target" in note,
      "the native target finds its oracle and says which one")

print()
if fails:
    print("FAILED %d check(s):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("all csmith --target guards green")
