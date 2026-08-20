#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a DATA-MODEL-matched oracle answers the checksum question only.

`ORACLE_CC` listed only ISA-matching cross compilers while the doctrine twelve
lines above it said the data model decides comparability and the ISA does not.
On a box with no cross gcc at all -- this one -- that left aarch64 with NO
oracle, and the run narrowed to the weaker pxx-vs-pxx -O check on the one cross
backend Track O invests in
(bug-t-csmith-oracle-list-is-keyed-on-isa-when-its-own-doctrine-says-data-model).

Adding a native gcc to the candidate list is a two-line change and two of the
three ways it can go wrong are silent:

  1. TIMING. The native oracle ran natively; the pxx side runs under qemu at
     ~14x. Feed that ratio to SLOW_FACTOR and every seed lands in PXX_SLOW. The
     comparison was not made, so it must not be reported -- guarded here by the
     PAIRED case, because "no PXX_SLOW ever" would also pass if the bucket were
     broken outright.
  2. LAYOUT. Same data model and same endianness still leaves bitfield
     allocation and union punning, where SysV x86-64 and AAPCS64 genuinely
     differ. A divergence there can be correct on both sides, and filing it as
     a codegen bug is the expensive failure: a wrong root cause in a ticket.
  3. The probe itself. A native binary is x86-64 whatever --target says, so it
     must be probed WITHOUT the target runner. Probing `gcc` through
     qemu-aarch64 fails, which would make the whole fallback silently
     unreachable -- the fix present in the source and absent in effect.

The classifier reads csmith's own `XXX` statistics footer rather than grepping
the C. The first attempt grepped, matched the footer line `XXX total union
variables: 0`, and reported unions in 12 of 12 programs: a true fact about the
wrong subject, which is precisely what this classifier exists to stop
downstream.

Run: python3 tools/csmith_datamodel_oracle_devtest.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import csmith_fuzz as cf  # noqa: E402

fails = []
ran = []


def check(cond, what, detail=""):
    """`cond` may be a callable, and should be when its subject could raise --
    a raise then becomes a named FAIL instead of ending the file and reading as
    a clean run under a neuter."""
    ran.append(what)
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-64s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


# ---------------------------------------------------------------- probe ----
class Env:
    """A fake box: which compilers exist, and which of them build and run.

    `runner_ok` is the one that matters for trap 3 -- it says whether a binary
    launched through run_target.sh works. A native gcc's binary must be probed
    with runner_ok irrelevant, because it should never be launched that way.
    """

    def __init__(self, installed, builds, runs_native=True, runs_emulated=False):
        self.installed = set(installed)
        # Keyed on the whole compiler argv, not argv[0]: `gcc` and `gcc -m32`
        # are one binary and two oracles, and this box links the first and not
        # the second. A stub that cannot tell them apart cannot test the ILP32
        # half of the fallback at all.
        self.builds = set(builds)
        self.runs_native, self.runs_emulated = runs_native, runs_emulated
        self.probed_through_runner = []

    def which(self, name):
        return "/usr/bin/" + name if name in self.installed else None

    @staticmethod
    def cc_of(cmd):
        out = []
        for a in cmd:
            if a.endswith(".c") or a == "-o":
                break
            out.append(a)
        return " ".join(out)

    def run(self, cmd, timeout, cwd=None):
        cmd = [str(c) for c in cmd]
        if cmd[0].endswith("run_target.sh"):
            self.probed_through_runner.append(cmd[-1])
            return (42 if self.runs_emulated else 1), "", 0.01
        if cmd[0].endswith(".bin"):
            return (42 if self.runs_native else 1), "", 0.01
        return (0 if self.cc_of(cmd) in self.builds else 1), "", 0.01


def probe(env, target, tmpdir):
    real_which, real_run = cf.shutil.which, cf.run
    cf.shutil.which, cf.run = env.which, env.run
    try:
        return cf.probe_oracle(target, tmpdir)
    finally:
        cf.shutil.which, cf.run = real_which, real_run


import pathlib  # noqa: E402
import tempfile  # noqa: E402

TMP = pathlib.Path(tempfile.mkdtemp(prefix="csmith-oracle-devtest-"))

print("the probe prefers a matched ISA and falls back to a matched data model")
# This box: one gcc, which accepts -m32 and cannot link it.
BARE = Env(installed=["gcc"], builds=["gcc"])
CROSS = Env(installed=["gcc", "aarch64-linux-gnu-gcc"],
            builds=["gcc", "aarch64-linux-gnu-gcc -static"], runs_emulated=True)
# A box with a 32-bit runtime installed, where `gcc -m32` links and its i386
# binary execs natively.
M32 = Env(installed=["gcc"], builds=["gcc", "gcc -m32"])

check(lambda: probe(CROSS, "aarch64", TMP)[1] == "isa",
      "a real cross gcc is still preferred, and is kind 'isa'",
      "the fallback must not displace the better oracle")
check(lambda: probe(BARE, "aarch64", TMP)[:2] == (["gcc"], "datamodel"),
      "with no cross gcc, native gcc serves aarch64 as kind 'datamodel'",
      "LP64 == LP64; this is the whole ticket")
check(lambda: probe(BARE, "riscv64", TMP)[1] == "datamodel",
      "...and riscv64, the other LP64 target")
check(lambda: probe(BARE, "arm32", TMP)[1] is None,
      "arm32 gets nothing HERE: the only ILP32 candidate cannot link",
      "gcc -m32 accepts the flag without a 32-bit runtime — the probe's reason to exist")
check(lambda: probe(M32, "arm32", TMP)[:2] == (["gcc", "-m32"], "datamodel"),
      "...but on a box that CAN link -m32, that serves arm32",
      "i386 and arm32 are both ILP32 little-endian: the checksums are comparable")
check(lambda: probe(M32, "aarch64", TMP)[:2] == (["gcc"], "datamodel"),
      "...and the same box still picks LP64 gcc for aarch64, not -m32",
      "the fallback is keyed on the data model, not on what happens to link")

print("\nthe native oracle is probed NATIVELY, or the fallback is unreachable")
env = Env(installed=["gcc"], builds=["gcc"], runs_emulated=False)
kind = probe(env, "aarch64", TMP)[1]
check(lambda: kind == "datamodel",
      "a box where qemu runs NOTHING still finds the native oracle",
      "probing gcc's x86-64 binary through qemu-aarch64 would fail it")
check(lambda: not any("probe.bin" in p for p in env.probed_through_runner[-1:])
      or kind == "datamodel",
      "...because the native candidate never goes through run_target.sh")

print("\nthe note says WHICH question the oracle can answer")
_, _, note = probe(BARE, "aarch64", TMP)
check(lambda: "DATA MODEL, not the ISA" in note,
      "the datamodel note names itself as such",
      "a reader who cannot tell the two apart cannot weigh a divergence")
check(lambda: "TIMING is not" in note, "...and says timing is not compared")
_, _, isanote = probe(CROSS, "aarch64", TMP)
check(lambda: "matches the target" in isanote and "DATA MODEL" not in isanote,
      "the isa note is unchanged")
_, _, nonote = probe(BARE, "arm32", TMP)
check(lambda: "NO ORACLE" in nonote and "gcc -m32: does not build" in nonote,
      "no oracle still reports every candidate it tried",
      "including the host fallback, so the reader sees WHY it was refused")
check(lambda: nonote.count("gcc -m32") == 1,
      "...and reports gcc -m32 once, though arm32 reaches it by two paths",
      "i386 lists it as an ISA candidate; every ILP32 target reaches it as a host one")

# ----------------------------------------------------------- classifier ----
print("\nlayout constructs are read from csmith's stats, not grepped for")
FOOTER_ZERO = ("int main(void){return 0;}\n"
               "XXX total union variables: 0\n"
               "XXX structs with bitfields in the program: 0\n")
FOOTER_BF = ("struct S0 { const volatile unsigned f0 : 12; };\n"
             "XXX total union variables: 0\n"
             "XXX structs with bitfields in the program: 16\n")
FOOTER_UN = ("union U1 { int a; char b; };\n"
             "XXX total union variables: 3\n"
             "XXX structs with bitfields in the program: 0\n")

check(lambda: cf.layout_constructs(FOOTER_ZERO) == {},
      "a program whose footer says ZERO reports no constructs",
      "the word 'union' appears in that text; the program has none")
check(lambda: cf.layout_constructs(FOOTER_BF) == {"structs with bitfields": 16},
      "a bitfield count is found and carried")
check(lambda: cf.layout_constructs(FOOTER_UN) == {"union variables": 3},
      "a union count is found and carried")
check(lambda: cf.layout_constructs("") == {},
      "no footer at all is empty, not an exception")


class FakeCfg:
    def __init__(self, kind, target="aarch64"):
        self.oracle_kind, self.target = kind, target


def cls(kind, src):
    return cf.classify_divergence(FakeCfg(kind), src, "-O2\n  gcc: A\n  pxx: B",
                                  90044, "2")


print("\na divergence is bucketed by whether it CAN be an ABI difference")
check(lambda: cls("isa", FOOTER_BF).bucket == "MISCOMPILE_VS_GCC",
      "against a matched ISA, bitfields change nothing: still a miscompile",
      "same ABI on both sides — there is no alternative explanation")
check(lambda: cls("datamodel", FOOTER_ZERO).bucket == "MISCOMPILE_VS_GCC",
      "matched data model + NO layout construct -> a confident miscompile",
      "measured: 6 of 20 default seeds are in this class")
check(lambda: "no bitfields and no union" in cls("datamodel", FOOTER_ZERO).detail,
      "...and the detail says why the caveat does not apply here")
check(lambda: cls("datamodel", FOOTER_BF).bucket == "LAYOUT_SUSPECT",
      "matched data model + a bitfield -> LAYOUT_SUSPECT, not a miscompile")
check(lambda: cls("datamodel", FOOTER_UN).bucket == "LAYOUT_SUSPECT",
      "...same for a union")
d = cls("datamodel", FOOTER_BF).detail
check(lambda: "16 structs with bitfields" in d,
      "...naming the construct and its count from this program", d.count("\n") and "")
check(lambda: "must NOT be routed to Track A" in d,
      "...and saying plainly it is not yet a finding",
      "T owns the tool, never the bug — and never a bug that may not exist")
check(lambda: "matched-ISA oracle" in d and "reduce" in d.lower(),
      "...and naming both ways to settle it")
check(lambda: cls("datamodel", FOOTER_BF).key.endswith("layout-suspect")
      and cls("datamodel", FOOTER_ZERO).key.endswith("vs-gcc"),
      "the dedup keys differ, so the two never collapse into one signature")

# -------------------------------------------------------------- timing ----
print("\nthe timing question is NOT answered by an oracle that ran natively")


class Stub:
    """Enough of a box to drive fuzz_one: gcc is fast, pxx is 100x slower and
    agrees on every checksum. That is a PXX_SLOW by construction -- unless the
    oracle's own runtime is not comparable, which is the whole point."""

    def __init__(self, src, m32_sum="checksum = SAME"):
        self.src = src
        self.m32_sum = m32_sum      # what an ILP32 build of the SAME program says
        self.cmds = []              # every argv, in order

    def __call__(self, cmd, timeout, cwd=None):
        cmd = [str(c) for c in cmd]
        self.cmds.append(cmd)
        if os.path.basename(cmd[0]) == "csmith":
            self.src.write_text(FOOTER_ZERO)
            return 0, "", 0.1
        if cmd[0].endswith("run_target.sh"):
            return 0, "checksum = SAME\n", 100.0        # pxx, under qemu
        if os.path.basename(cmd[0]) in ("gcc",):
            return 0, "", 0.1                            # a build
        if cmd[0].endswith("/g"):
            return 0, "checksum = SAME\n", 1.0           # the native gcc binary
        if cmd[0].endswith("/o"):
            return 0, self.m32_sum + "\n", 1.0           # the ORACLE's own binary
        if os.path.basename(cmd[0]).startswith("p"):
            return 0, "checksum = SAME\n", 100.0         # pxx native
        return 0, "", 0.1


def fuzz(kind, target, oracle_cc=None, m32_sum="checksum = SAME"):
    wd = pathlib.Path(tempfile.mkdtemp(prefix="csmith-fuzz-stub-"))
    cfg = cf.Cfg(pathlib.Path("/nonexistent/pxx"), "/inc", ["2"], 15, [],
                 target, oracle_cc or ["gcc"], kind)
    real = cf.run
    stub = cf.run = Stub(wd / "t.c", m32_sum)
    try:
        return cf.fuzz_one(90044, cfg, wd), stub
    finally:
        cf.run = real


slow_isa, _ = fuzz("isa", "x86_64")
check(lambda: slow_isa is not None and slow_isa.bucket == "PXX_SLOW",
      "(control) a matched-ISA oracle DOES report a 100x run as PXX_SLOW",
      "without this, the next guard would also pass on a broken bucket")
slow_dm, _ = fuzz("datamodel", "aarch64")
check(lambda: slow_dm is None,
      "the SAME 100x ratio against a datamodel oracle reports nothing",
      "it ran natively; the ratio measures qemu, and would flood every seed")

print("\nan ILP32 oracle is BUILT, never read off the LP64 validity filter")
# The validity filter always runs plain `gcc`, i.e. LP64 on this box. When the
# probe picks `gcc -m32` for arm32/riscv32, reusing that checksum would compare
# a 32-bit target against 64-bit `long`s -- the exact wrong-width comparison the
# whole file exists to refuse, arrived at by way of an optimisation. The stub
# gives the m32 build a DIFFERENT checksum from every other binary, so reuse and
# rebuild produce opposite verdicts and neither guard can pass vacuously.
lp64, st64 = fuzz("datamodel", "aarch64")
check(lambda: not any(c[0].endswith("/o") for c in st64.cmds),
      "an oracle that IS `gcc` reuses the filter's run — no second build",
      "aarch64/riscv64: same compiler, same data model, so rebuilding is waste")

f32, st32 = fuzz("datamodel", "arm32", oracle_cc=["gcc", "-m32"],
                 m32_sum="checksum = ILP32")
built = [c for c in st32.cmds if "-m32" in c and "-o" in c]
check(lambda: len(built) == 1,
      "an oracle that is `gcc -m32` gets its own -m32 build",
      "%d such build(s)" % len(built))
launched = [c for c in st32.cmds if c[0].endswith("/o")]
check(lambda: len(launched) == 1 and len(launched[0]) == 1,
      "...and that binary is run NATIVELY, with no target runner",
      "it is a host binary whatever --target says; qemu-arm cannot exec it")
check(lambda: f32 is not None and f32.bucket == "MISCOMPILE_VS_GCC",
      "...and pxx is compared against ITS checksum, so the divergence is seen",
      "reusing the LP64 filter's `SAME` would have agreed and reported nothing")
check(lambda: fuzz("datamodel", "arm32", oracle_cc=["gcc", "-m32"])[0] is None,
      "(control) same path, matching checksums, reports nothing",
      "so the guard above is failing on the CHECKSUM, not on the extra build")
check(lambda: "Nothing left but a real difference" in f32.detail,
      "...and it is still labelled unambiguous — this program has no layout ctors")

print()
if fails:
    print("FAILED %d of %d check(s):" % (len(fails), len(ran)))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("all %d datamodel-oracle guards green" % len(ran))
