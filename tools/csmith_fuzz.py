#!/usr/bin/env python3
"""Differential fuzzing: pxx vs gcc, on random C programs from csmith.

csmith generates C programs that are free of undefined behaviour by construction and
end by printing a checksum of every global. That gives us an oracle with no judgement
calls in it: build the same program with gcc and with pxx, run both, and the checksums
must match. If they differ, one of the two compilers is wrong -- and it is not gcc.

We also build with pxx at several -O levels and compare them against each other. A
disagreement between our own -O0 and -O2 is a miscompile we own outright, with no
question of who is right.

Findings are bucketed, deduplicated by (bucket, first line of the error), and written
to the output directory with the generating seed, so any hit reproduces exactly:

    tools/csmith_fuzz.py --iters 200
    tools/csmith_fuzz.py --seed 12345          # replay one seed
    tools/csmith_fuzz.py --target aarch64      # cross-compile, run under qemu

`--target` builds with `pxx --target=<arch>` and runs the result through
tools/run_target.sh, which execs it natively or under qemu-user. What it does NOT
do is keep the gcc oracle by default: the checksum a csmith program prints depends
on the DATA MODEL (`long` is 64-bit under LP64 and 32-bit under ILP32), so a native
x86-64 gcc and an ILP32 target disagree for reasons that are not miscompiles. The
harness looks for a gcc whose data model matches the target -- a CROSS one first,
and failing that a native one, which decides every checksum question even though
it cannot decide a timing one -- and if it can find neither it says so and drops
the vs-gcc comparison for the run rather than filing MISCOMPILE_VS_GCC on a
`long` width. The pxx-vs-pxx -O comparison is unaffected --
it is a comparison of one target against itself and is the finding we own outright.

Buckets, worst first:
  MISCOMPILE_VS_GCC   pxx and gcc both ran and printed DIFFERENT checksums
  MISCOMPILE_OPT      two pxx -O levels printed different checksums
  LAYOUT_SUSPECT      pxx and gcc disagreed, but the oracle matched only the
                      DATA MODEL and the program contains bitfields or unions --
                      the two things two ABIs may legitimately lay out
                      differently at the same widths. Ranked with the
                      miscompiles on purpose: it may be one. Not to be routed
                      to Track A until reduced or re-checked against a
                      matched-ISA oracle.
  PXX_CRASH           pxx's binary died (signal / non-zero exit)
  PXX_COMPILE_FAIL    pxx could not compile it (a frontend or codegen gap)
  PXX_TIMEOUT         pxx's binary did not finish even at a limit scaled off
                      the oracle's own runtime -- i.e. it really is hung
  PXX_SLOW            pxx's binary FINISHED and agreed with gcc, but took more
                      than SLOW_FACTOR x the oracle. A hint for Track O, not a
                      defect: a csmith program is pathological by construction.
  (gcc failures and gcc timeouts are discarded -- that seed is simply skipped)
"""

import argparse
import hashlib
import os
import random
import shutil
import subprocess
import sys
import time
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def find_csmith_include():
    """csmith.h: the vendored copy first, then a system install."""
    for p in (ROOT / "library_candidates/csmith/include",
              Path("/usr/include/csmith"),
              Path("/usr/local/include/csmith")):
        if (p / "csmith.h").is_file():
            return p
    sys.exit("csmith.h not found. Run: tools/install_lib_candidates.sh csmith\n"
             "(and make sure the `csmith` generator itself is on PATH)")


def run(cmd, timeout, cwd=None):
    """-> (rc, stdout+stderr, elapsed_seconds). rc is None on timeout.

    The elapsed time is returned for EVERY run, not just the ones we time on
    purpose, because the oracle's runtime is what the pxx limit is scaled off
    (see fuzz_one) and it is free to measure.
    """
    t0 = time.monotonic()
    try:
        p = subprocess.run(cmd, cwd=cwd, timeout=timeout,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        return (p.returncode, p.stdout.decode("utf-8", "replace"),
                time.monotonic() - t0)
    except subprocess.TimeoutExpired:
        return None, "<timeout>", time.monotonic() - t0
    except FileNotFoundError as e:
        sys.exit(f"missing tool: {e}")


# A fixed wall-clock limit cannot tell "hung" from "slower than the limit", and
# the difference is a reader's afternoon: a hang means a control-flow bug and
# gets chased like one. Seed 90044 sat in PXX_TIMEOUT for a run while pxx took
# 18.2s against gcc -O0's 6.9s -- both finished, both agreed.
#
# So scale the limit off the ORACLE, which the harness has already run and
# therefore already knows the cost of, and keep the fixed limit as a FLOOR so a
# millisecond-fast oracle cannot squeeze the budget to nothing.
TIMEOUT_FACTOR = 20      # beyond this multiple of the oracle, call it hung
SLOW_FACTOR = 4          # finished, agreed, but this much slower -> PXX_SLOW
# Ratios computed against a very short oracle are timer noise, not information:
# a 5 ms oracle makes an ordinary 200 ms run look 40x slow. Require the pxx side
# to be slow in ABSOLUTE terms too before the ratio is allowed to mean anything.
SLOW_MIN_SEC = 1.0

# Emulation has no oracle to scale against when there is no cross gcc, so the
# limit falls back to the FLAT --timeout -- which is exactly the failure mode this
# harness was fixed for. qemu-user costs roughly an order of magnitude, so a flat
# budget written for native execution has to be widened or every emulated run is a
# "hang". The PXX_TIMEOUT detail says which of the two budgets was in force so the
# reader knows how much to trust it.
#
# The number is anchored on one measurement (seed 90044, 2026-08-19, plexus):
#     gcc -O0 native        12.92s   <- the shape a 15s default budget assumes
#     pxx -O0 native        46.27s   ( 3.6x the oracle )
#     pxx -O0 qemu-aarch64 187.96s   ( 4.1x native, 14.5x the oracle )
# So 12 was too small by measurement, not by taste: that legitimate run needs
# 188s and the old floor killed it at 180s. 30 gives ~2.4x headroom over the only
# sample we have -- one seed is not a distribution, and qemu variance plus a
# heavier program eat headroom fast -- while still bounding a genuine hang at
# 7.5 minutes rather than letting it run all night.
EMU_TIMEOUT_FACTOR = 30

# The data model decides whether a checksum is comparable at all; the ISA does
# not. csmith programs are UB-free and deterministic, so two builds of one program
# agree when `long`/pointer widths agree -- and disagree, legitimately, when they
# do not. (Every target here is little-endian; a big-endian target would need the
# same treatment for byte order.)
TARGETS = {
    "x86_64": "LP64",
    "i386": "ILP32",
    "aarch64": "LP64",
    "arm32": "ILP32",
    "riscv32": "ILP32",
    "riscv64": "LP64",
}

# Candidate oracle compilers per target, in preference order. Each is PROBED --
# built and run -- rather than trusted because the binary exists on PATH: this box
# has a `gcc` that accepts -m32 and cannot link it (no 32-bit runtime), which is
# precisely the case a `command -v` check gets wrong.
ORACLE_CC = {
    "x86_64": [["gcc"]],
    "i386": [["gcc", "-m32"], ["i686-linux-gnu-gcc"]],
    "aarch64": [["aarch64-linux-gnu-gcc", "-static"]],
    "arm32": [["arm-linux-gnueabihf-gcc", "-static"],
              ["arm-linux-gnueabi-gcc", "-static"]],
    "riscv32": [["riscv32-linux-gnu-gcc", "-static"]],
    "riscv64": [["riscv64-linux-gnu-gcc", "-static"]],
}

# The DATA-MODEL fallback, and the second half of the doctrine above. When no
# cross gcc exists for a target, a NATIVE compiler whose data model matches is
# still a legitimate checksum oracle -- that is what "the ISA does not decide"
# means. Keyed by data model, probed NATIVELY (no target runner: these binaries
# are x86-64, and running one through qemu-aarch64 is how a naive reading of
# this fix fails its own probe).
#
# It buys the target Track O actually invests in. On this box every cross gcc is
# absent -- aarch64/arm/riscv/i686 all missing, and `gcc -m32` accepts the flag
# without being able to link -- so aarch64 had NO oracle at all and the run
# silently narrowed to the weaker pxx-vs-pxx -O check.
#
# One thing this oracle CANNOT say, enforced below rather than left to a reader:
# TIMING. It ran natively; the pxx side runs under qemu at ~14x. Feeding that
# ratio to SLOW_FACTOR would file every single seed as PXX_SLOW. `oracle_sec` is
# withheld, and the existing "no timing -> no slow verdict, flat budget" path
# already handles the rest.
#
# The other limit is LAYOUT, and it is handled by classify_divergence() rather
# than by narrowing what we generate. Same data model and same endianness still
# leaves bitfield allocation and union punning, where SysV x86-64 and AAPCS64
# legitimately differ -- so a divergence can be correct on both sides, and we
# already have an open finding in that area (bug-c-bitfield-packing-sizeof-vs-gcc).
HOST_ORACLE = [(["gcc"], "LP64"), (["gcc", "-m32"], "ILP32")]

# The compiler the validity filter runs on every seed. Named because fuzz_one
# reuses that build's checksum when the chosen oracle IS this compiler, and
# must NOT when it is a different one at the same data model.
VALIDITY_CC = ["gcc"]

# i386 binaries exec natively on an x86-64 kernel (run_target.sh falls back to
# qemu-i386 only if that fails), so they are not "emulated" for timing purposes.
NATIVE_TARGETS = ("x86_64", "i386")


class Cfg:
    """Everything fuzz_one needs that does not change between seeds.

    A parameter object rather than eight positionals: --target added four
    correlated settings (how to invoke pxx, how to RUN what it emits, which
    oracle is comparable, whether a timing ratio means anything) and they are
    only ever correct together.
    """
    __slots__ = ("pxx", "inc", "opts", "timeout", "csmith_args", "target",
                 "oracle_cc", "oracle_kind", "runner", "emulated")

    def __init__(self, pxx, inc, opts, timeout, csmith_args, target, oracle_cc,
                 oracle_kind=None):
        self.pxx, self.inc, self.opts = pxx, inc, opts
        self.timeout, self.csmith_args = timeout, csmith_args
        self.target, self.oracle_cc = target, oracle_cc
        # "isa" = built for the target and run through the target runner;
        # checksum AND timing are comparable. "datamodel" = a native compiler
        # with the same long/pointer widths, run natively; the CHECKSUM is
        # comparable and nothing else is. None = no oracle at all.
        self.oracle_kind = oracle_kind
        # x86_64 keeps the bare exec it has always had: run_target.sh would only
        # add a shell to every timed run, and timing is what the budget is
        # scaled off.
        self.runner = [] if target == "x86_64" else [str(ROOT / "tools/run_target.sh"), target]
        self.emulated = target not in NATIVE_TARGETS

    def pxx_cmd(self, opt, src, out):
        cmd = [str(self.pxx)]
        if opt != "default":
            cmd.append(f"-O{opt}")
        if self.target != "x86_64":
            cmd.append(f"--target={self.target}")
        # pxx wants -Ipath joined, not -I path
        return cmd + [f"-I{self.inc}", str(src), str(out)]


def probe_oracle(target, workdir):
    """The first candidate compiler that BUILDS and RUNS for this target, or None.

    Returns (argv, kind, note). `kind` is "isa" (built for the target and run
    through the target runner -- checksum AND timing comparable), "datamodel"
    (a native compiler with the same long/pointer widths, run natively -- only
    the CHECKSUM is comparable), or None.

    `note` is what the report prints, and it is printed whether or not a
    compiler was found: dropping the vs-gcc comparison silently would turn "we
    did not check" into "we checked and it agreed". It names WHICH kind was
    found for the same reason -- the two answer different questions, and a
    reader who cannot tell them apart cannot weigh a divergence.
    """
    src = workdir / "probe.c"
    src.write_text("int main(void){return 42;}\n")
    runner = [] if target == "x86_64" else [str(ROOT / "tools/run_target.sh"), target]
    tried, tried_cmds = [], []
    for cc in ORACLE_CC.get(target, []):
        tried_cmds.append(cc)
        # which() first only so a missing cross compiler does not hit run()'s
        # sys.exit on FileNotFoundError -- "no such compiler" is an ordinary
        # answer here, not a broken environment. The real test is still the
        # build-and-run below: this box has a gcc that ACCEPTS -m32 and cannot
        # link it, which is exactly what a which() check alone gets wrong.
        if not shutil.which(cc[0]):
            tried.append(f"{cc[0]}: not installed")
            continue
        binp = workdir / "probe.bin"
        rc, _, _ = run(cc + [str(src), "-o", str(binp)], 60)
        if rc != 0:
            tried.append(f"{cc[0]}: does not build")
            continue
        rc, _, _ = run(runner + [str(binp)], 60)
        if rc != 42:
            tried.append(f"{cc[0]}: builds but does not run here")
            continue
        return cc, "isa", f"oracle: {' '.join(cc)} ({TARGETS[target]}, matches the target)"

    # No cross compiler. A NATIVE one with the same data model still decides
    # every checksum question -- run it natively (runner = []), because these
    # binaries are x86-64 whatever the target is.
    model = TARGETS[target]
    for cc, cc_model in HOST_ORACLE:
        if cc_model != model:
            continue
        if cc in tried_cmds:
            continue          # already probed above; do not report it twice
        if not shutil.which(cc[0]):
            tried.append(f"{' '.join(cc)}: not installed")
            continue
        binp = workdir / "probe.bin"
        rc, _, _ = run(cc + [str(src), "-o", str(binp)], 60)
        if rc != 0:
            tried.append(f"{' '.join(cc)}: does not build")
            continue
        rc, _, _ = run([str(binp)], 60)     # NATIVE, deliberately not `runner`
        if rc != 42:
            tried.append(f"{' '.join(cc)}: builds but does not run here")
            continue
        return cc, "datamodel", (
            "oracle: %s (%s, matches the DATA MODEL, not the ISA) -- runs "
            "natively.\n  Checksums are compared; TIMING is not (PXX_SLOW is "
            "off this run), and a divergence in a program with bitfields or "
            "unions is filed LAYOUT_SUSPECT rather than as a miscompile."
            % (" ".join(cc), model))

    detail = "; ".join(tried) or "no candidate compiler known"
    return None, None, ("NO ORACLE for %s (%s) -- %s.\n"
                  "  MISCOMPILE_VS_GCC and PXX_SLOW are NOT CHECKED this run; "
                  "pxx-vs-pxx -O comparison still is." % (target, TARGETS[target], detail))


LAYOUT_KEYS = {
    "total union variables": "union variables",
    "structs with bitfields in the program": "structs with bitfields",
}


def layout_constructs(src_text):
    """Which layout-sensitive constructs this PROGRAM actually contains.

    Read out of csmith's own `XXX ...` statistics footer, which counts them per
    program -- not grepped for. A first attempt at this regexed the C for
    `\bunion\b` and reported unions in 12 of 12 programs; every hit was the
    footer line `XXX total union variables: 0`. A true fact about the wrong
    subject, which is the exact failure this function exists to prevent
    downstream, so it is worth one sentence here.

    Only these two matter. csmith's checksum hashes named FIELDS through
    transparent_crc, not raw struct bytes, so ordinary padding and alignment
    differences cannot reach it. What can: bitfield allocation (where bits land
    inside the storage unit, which SysV x86-64 and AAPCS64 genuinely disagree
    about) and union punning (reading a member other than the one written).
    """
    found = {}
    for line in src_text.splitlines():
        if not line.startswith("XXX "):
            continue
        key, _, val = line[4:].strip().rpartition(":")
        if key in LAYOUT_KEYS:
            try:
                n = int(val)
            except ValueError:
                continue
            if n:
                found[LAYOUT_KEYS[key]] = n
    return found


DATAMODEL_UNAMBIGUOUS = """
The oracle matched this target's DATA MODEL, not its ISA (see HOST_ORACLE), so
an ABI disagreement would normally be a live alternative explanation. It is not
here: csmith reports this program contains no bitfields and no union variables,
and its checksum hashes named fields rather than raw bytes, so padding and
alignment cannot reach it either. Nothing left but a real difference."""


def classify_divergence(cfg, src_text, base_detail, seed, opt):
    """A checksum divergence, bucketed by whether it CAN be an ABI difference.

    Against a matched-ISA oracle it cannot be, and this returns the finding
    unchanged. Against a matched-DATA-MODEL oracle it can, and the campaign's
    real cost has always been reduction rather than discovery -- so the split is
    made here, at the hit, out of facts the diverging program already carries.

    Measured over 20 default seeds: 6 carry neither construct. Those 30% become
    confident findings immediately instead of joining a queue of maybes, and the
    other 70% are labelled rather than confidently misfiled.

    Deliberately NOT done by re-running the seed with --no-bitfields
    --no-packed-struct --no-unions and seeing whether the disagreement survives.
    That sounds like reduction and is not: csmith's option set is part of its RNG
    input, so the same seed under different flags is a DIFFERENT program --
    measured, seed 90044 goes 1879 -> 3373 lines with a different checksum. A
    layout-free program agreeing tells you almost nothing, because layout-free
    programs agreeing is the norm whatever caused the original. (The converse
    does hold: if such a run diverges too, that is a fresh unambiguous finding --
    on its own merits, as its own seed, not as evidence about this one.)

    Nor is the answer to stop generating the constructs. Bitfields produced
    three of this campaign's first nine bugs; sweeping them out to make the
    remainder easier to read trades the richest territory for convenience. Run
    wide, classify on hit.
    """
    if cfg.oracle_kind != "datamodel":
        return Finding("MISCOMPILE_VS_GCC", seed, base_detail, f"O{opt}:vs-gcc")
    found = layout_constructs(src_text)
    if not found:
        return Finding("MISCOMPILE_VS_GCC", seed,
                       base_detail + "\n" + DATAMODEL_UNAMBIGUOUS,
                       f"O{opt}:vs-gcc")
    what = ", ".join("%d %s" % (n, k) for k, n in sorted(found.items()))
    return Finding("LAYOUT_SUSPECT", seed,
                   base_detail + """

NOT a finding yet, and must NOT be routed to Track A on this evidence. The
oracle matched this target's DATA MODEL, not its ISA, and this program contains
%s -- the two places where SysV x86-64 and AAPCS64
legitimately disagree at the same long/pointer widths. Both sides may be
correct.

To settle it: reduce until no bitfield or union remains and the divergence
survives, or re-run this seed against a matched-ISA oracle (a cross gcc for
%s), which has no such ambiguity.""" % (what, cfg.target),
                   f"O{opt}:layout-suspect")


class Finding:
    __slots__ = ("bucket", "seed", "detail", "key")

    def __init__(self, bucket, seed, detail, key):
        self.bucket, self.seed, self.detail, self.key = bucket, seed, detail, key


def first_error_line(text):
    """The signature we deduplicate on: csmith throws thousands of programs at the
    same handful of gaps, and 500 copies of one bug is not 500 bugs."""
    for line in text.splitlines():
        line = line.strip()
        if "error:" in line:
            # strip the path/line prefix so the same gap in different programs collides
            return line.split("error:", 1)[1].strip()[:120]
    for line in text.splitlines():
        if line.strip():
            return line.strip()[:120]
    return "(no output)"


SKIP = "skip"   # the seed told us nothing (the validity filter, or the
                # oracle, could not build or run the program)


def fuzz_one(seed, cfg, workdir):
    src = workdir / "t.c"
    rc, out, _ = run(["csmith", "--seed", str(seed), "--output", str(src)] + cfg.csmith_args, 120)
    if rc != 0 or not src.is_file():
        return SKIP  # generator hiccup

    # ---- the validity filter: the NATIVE gcc, on every run ----------------
    # Separate from the ORACLE below, and kept even when it cannot serve as one.
    # It answers "is this program buildable and runnable at all", and without it a
    # generator hiccup on a cross run would be filed as PXX_COMPILE_FAIL -- a gap
    # in our frontend that isn't one.
    gcc_bin = workdir / "g"
    rc, out, _ = run(VALIDITY_CC + ["-O0", f"-I{cfg.inc}", "-w", str(src),
                                    "-o", str(gcc_bin)], 180)
    if rc != 0:
        return SKIP  # gcc won't build it -> not our problem
    rc, gcc_out, gcc_sec = run([str(gcc_bin)], cfg.timeout)
    if rc != 0 or "checksum" not in gcc_out:
        return SKIP  # gcc's own binary misbehaved or hung

    # An emulated program is an order of magnitude slower than a native one, so
    # every budget below starts from a widened floor. Native targets keep the
    # exact floor they had.
    floor = cfg.timeout * (EMU_TIMEOUT_FACTOR if cfg.emulated else 1)

    # ---- the oracle, when one exists for THIS target ----------------------
    # It has to be run the way the pxx binaries are run (same emulation, same
    # runner), or the ratio the timeout is scaled off measures qemu rather than
    # the compiler.
    oracle_sum = oracle_sec = None
    if cfg.oracle_cc is not None:
        if cfg.target == "x86_64":
            oracle_sum, oracle_sec = gcc_out.strip(), gcc_sec   # it IS the native gcc
        elif cfg.oracle_kind == "datamodel":
            # Run NATIVELY in both arms -- this oracle's binary is the host's
            # whatever --target says -- and `oracle_sec` stays None in both.
            # That is deliberate: the pxx side runs under qemu at ~14x, so every
            # seed would clear SLOW_FACTOR and PXX_SLOW would fill with noise.
            # Checksum comparability and TIMING comparability are different
            # questions with different preconditions (data model for one,
            # execution environment for the other), and one oracle must not be
            # taken to answer both. The existing oracle_sec-is-None path already
            # gives the flat budget and suppresses the slow verdict.
            if cfg.oracle_cc == VALIDITY_CC:
                # Identical to the validity filter above, so reuse its result:
                # zero extra work, and no second definition of "the native
                # build". This is the aarch64/riscv64 case, and the whole
                # ticket -- that checksum was already being computed and thrown
                # away because the guard asked about the ISA.
                oracle_sum = gcc_out.strip()
            else:
                # NOT the same compiler: `gcc -m32` is an ILP32 oracle and
                # `gcc_out` came from an LP64 build. Reusing it here would
                # compare a 32-bit target against 64-bit `long`s -- the exact
                # wrong-width comparison this file exists to refuse, arrived at
                # by way of an optimisation.
                obin = workdir / "o"
                rc, _, _ = run(cfg.oracle_cc + ["-O0", f"-I{cfg.inc}", "-w",
                                                str(src), "-o", str(obin)], 180)
                if rc != 0:
                    return SKIP
                rc, oout, _ = run([str(obin)], floor)     # native, not cfg.runner
                if rc != 0 or "checksum" not in oout:
                    return SKIP
                oracle_sum = oout.strip()
        else:
            obin = workdir / "o"
            rc, _, _ = run(cfg.oracle_cc + ["-O0", f"-I{cfg.inc}", "-w", str(src),
                                            "-o", str(obin)], 180)
            if rc != 0:
                return SKIP  # the target oracle won't build it -> tells us nothing
            rc, oout, oracle_sec = run(cfg.runner + [str(obin)], floor)
            if rc != 0 or "checksum" not in oout:
                return SKIP
            oracle_sum = oout.strip()

    # Now that the oracle's cost is known, give pxx a budget proportional to it
    # rather than the flat one that misfiled seed 90044 as a hang. With no oracle
    # there is nothing to scale off and the budget is flat again -- the detail
    # says so, because that is the case where PXX_TIMEOUT is least trustworthy.
    if oracle_sec is not None:
        run_limit = max(floor, TIMEOUT_FACTOR * oracle_sec)
        scale = f"{TIMEOUT_FACTOR}x the oracle's {oracle_sec:.1f}s"
    else:
        run_limit = floor
        scale = ("a FLAT budget: %s, so nothing to scale off -- treat as a "
                 "hint, not a hang"
                 % ("the oracle ran natively and this target does not"
                    if cfg.oracle_kind == "datamodel"
                    else "no oracle for this target"))

    # ---- pxx, at each -O level -------------------------------------------
    results, secs = {}, {}
    for opt in cfg.opts:
        pbin = workdir / f"p{opt}"
        rc, cout, _ = run(cfg.pxx_cmd(opt, src, pbin), 300)
        if rc != 0:
            return Finding("PXX_COMPILE_FAIL", seed,
                           f"-O{opt}\n{cout}", f"O{opt}:{first_error_line(cout)}")

        rc, rout, sec = run(cfg.runner + [str(pbin)], run_limit)
        if rc is None:
            return Finding("PXX_TIMEOUT", seed,
                           f"-O{opt} did not finish in {run_limit:.1f}s ({scale})",
                           f"O{opt}:timeout")
        if rc != 0 or "checksum" not in rout:
            return Finding("PXX_CRASH", seed,
                           f"-O{opt} exit={rc}\n{rout}", f"O{opt}:exit{rc}")
        results[opt] = rout.strip()
        secs[opt] = sec

    # ---- compare ----------------------------------------------------------
    # Only against an oracle with the target's own data model. A native x86-64
    # checksum and an ILP32 target's checksum differ over `long` widths, and
    # filing that as MISCOMPILE_VS_GCC would be a true difference reported as the
    # wrong finding.
    if oracle_sum is not None:
        for opt, got in results.items():
            if got != oracle_sum:
                return classify_divergence(
                    cfg, src.read_text(),
                    f"-O{opt}\n  gcc: {oracle_sum}\n  pxx: {got}", seed, opt)

    distinct = set(results.values())
    if len(distinct) > 1:
        detail = "\n".join(f"  -O{o}: {v}" for o, v in sorted(results.items()))
        return Finding("MISCOMPILE_OPT", seed, "pxx disagrees with itself:\n" + detail,
                       "opt-levels-disagree")

    # Only now, with every checksum agreeing, is "slow" the interesting fact.
    # Deliberately after the comparisons: a wrong answer beats a slow one, and a
    # miscompile must never be filed as a performance note. And only against an
    # oracle that ran the same way we did -- a qemu run over a native oracle is a
    # measurement of qemu.
    if oracle_sec is None:
        return None
    slow = {o: s for o, s in secs.items()
            if s >= SLOW_MIN_SEC and oracle_sec > 0 and s > SLOW_FACTOR * oracle_sec}
    if slow:
        detail = "\n".join(f"  -O{o}: {s:.1f}s  ({s / oracle_sec:.1f}x)"
                           for o, s in sorted(slow.items()))
        worst = max(slow, key=slow.get)
        return Finding("PXX_SLOW", seed,
                       f"finished and AGREED with gcc, but slow.\n"
                       f"  gcc -O0: {oracle_sec:.1f}s\n{detail}\n\n"
                       f"Not a defect: a csmith program is pathological by "
                       f"construction, so this is a Track O hint, not a "
                       f"regression. Filed because the reproduction is worth "
                       f"keeping either way.",
                       f"O{worst}:slow")
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--iters", type=int, default=100, help="how many programs (default 100)")
    ap.add_argument("--seed", type=int, help="replay exactly one seed")
    ap.add_argument("--seed-start", type=int, default=1, help="first seed (default 1)")
    ap.add_argument("--opts", default="0,2", help="pxx -O levels to test (default 0,2)")
    ap.add_argument("--timeout", type=int, default=15, help="run timeout, seconds")
    ap.add_argument("--out", default="/tmp/csmith-findings", help="where to save hits")
    ap.add_argument("--compiler", default=str(ROOT / "compiler/pascal26"))
    ap.add_argument("--csmith-args", default="",
                    help="extra csmith flags, e.g. '--no-packed-struct --no-bitfields'")
    ap.add_argument("--target", default="x86_64", choices=sorted(TARGETS),
                    help="CPU target: build with pxx --target=<arch> and run the "
                         "result through tools/run_target.sh (default x86_64)")
    args = ap.parse_args()

    pxx = Path(args.compiler)
    if not pxx.is_file():
        sys.exit(f"no compiler at {pxx} (run: make all)")
    inc = find_csmith_include()
    opts = [o.strip() for o in args.opts.split(",") if o.strip()]
    csmith_args = args.csmith_args.split()

    seeds = [args.seed] if args.seed is not None else \
        list(range(args.seed_start, args.seed_start + args.iters))

    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    workdir = Path(tempfile.mkdtemp(prefix="csmith-fuzz-"))
    oracle_cc, oracle_kind, oracle_note = probe_oracle(args.target, workdir)
    cfg = Cfg(pxx, inc, opts, args.timeout, csmith_args, args.target, oracle_cc,
              oracle_kind)

    print(f"csmith fuzz: {len(seeds)} program(s), pxx -O{{{','.join(opts)}}}"
          + (f" --target={args.target}" if args.target != "x86_64" else "")
          + (" vs gcc -O0 oracle (%s)" % oracle_kind if oracle_cc else ""))
    print(f"  csmith.h: {inc}")
    print(f"  findings: {outdir}")
    print(f"  {oracle_note}")

    seen = {}          # dedup key -> first seed that showed it
    counts = {}
    skipped = 0
    agreed = 0
    try:
        for i, seed in enumerate(seeds, 1):
            f = fuzz_one(seed, cfg, workdir)
            if f is SKIP:
                skipped += 1
                # "gcc could not build it" reads as the ORACLE in a run whose
                # banner just said there is no oracle for this target, and a
                # reader then has to open the source to learn whether the skips
                # meant anything. It is the validity filter, which runs whether
                # or not an oracle exists; say so.
                print(f"  [{i}/{len(seeds)}] seed {seed}: skip (the native "
                      f"validity filter could not build/run it)",
                      flush=True)
                continue
            if f is None:
                agreed += 1
                print(f"  [{i}/{len(seeds)}] seed {seed}: ok", flush=True)
                continue

            # PXX_SLOW is a finding that AGREED -- that is its definition -- so
            # it must still count toward the oracle-agreement line, or adding
            # the bucket would silently make the harness look less correct.
            if f.bucket == "PXX_SLOW":
                agreed += 1
            counts[f.bucket] = counts.get(f.bucket, 0) + 1
            dedup = f"{f.bucket}|{f.key}"
            if dedup in seen:
                print(f"  [{i}/{len(seeds)}] seed {seed}: {f.bucket} "
                      f"(same as seed {seen[dedup]})", flush=True)
                continue
            seen[dedup] = seed

            # save it: the .c, the detail, and the exact command to reproduce
            d = outdir / f"{f.bucket}-{seed}"
            d.mkdir(exist_ok=True)
            shutil.copy(workdir / "t.c", d / "t.c")
            (d / "REPRO.md").write_text(
                f"# {f.bucket} — csmith seed {seed}\n\n"
                f"{f.detail}\n\n"
                f"## Reproduce\n\n```sh\n"
                f"csmith --seed {seed} {' '.join(csmith_args)} --output t.c\n"
                + (f"{' '.join(oracle_cc)} -O0 -w -I{inc} t.c -o t_gcc && "
                   f"{' '.join(cfg.runner)} ./t_gcc\n" if oracle_cc else
                   f"# no oracle for {args.target}: the checksum below was NOT "
                   f"compared against gcc\n")
                + f"{' '.join(cfg.pxx_cmd(opts[0], 't.c', 't_pxx'))} && "
                  f"{' '.join(cfg.runner)} ./t_pxx\n```\n\n"
                + f"Or: `tools/csmith_fuzz.py --seed {seed}"
                + (f" --target={args.target}" if args.target != "x86_64" else "")
                + "`\n")
            print(f"  [{i}/{len(seeds)}] seed {seed}: *** {f.bucket} *** -> {d}", flush=True)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print()
    print("== csmith fuzz report ==")
    if oracle_cc and oracle_kind == "datamodel":
        # An oracle that answered one of the two questions must not be reported
        # as though it answered both. Same rule as the no-oracle branch below,
        # one notch finer.
        print(f"  {agreed}/{len(seeds)} agreed with the gcc oracle"
              + (f"  ({skipped} skipped)" if skipped else ""))
        print("  NOT CHECKED: the slow ratio — the oracle matched "
              f"{args.target}'s data model, not its ISA, and ran natively.")
    elif oracle_cc:
        print(f"  {agreed}/{len(seeds)} agreed with the gcc oracle"
              + (f"  ({skipped} skipped)" if skipped else ""))
    else:
        # Never print the agreement line without an oracle: "N/M agreed" read on
        # a run that compared nothing is the whole class of error this harness
        # keeps finding in itself.
        print(f"  {agreed}/{len(seeds)} ran clean across pxx -O levels"
              + (f"  ({skipped} skipped)" if skipped else ""))
        print(f"  NOT CHECKED: agreement with gcc, and the slow ratio — "
              f"no oracle with {args.target}'s data model ({TARGETS[args.target]}).")
    if not counts:
        print("  no findings")
        return 0
    for bucket in ("MISCOMPILE_VS_GCC", "MISCOMPILE_OPT", "LAYOUT_SUSPECT",
                   "PXX_CRASH", "PXX_COMPILE_FAIL", "PXX_TIMEOUT", "PXX_SLOW"):
        if bucket in counts:
            uniq = sum(1 for k in seen if k.startswith(bucket + "|"))
            print(f"  {bucket:20s} {counts[bucket]:4d} hit(s), {uniq} distinct")
    print(f"\n  saved to {outdir}")
    # A miscompile is a hard failure; gaps and crashes are findings to triage.
    # LAYOUT_SUSPECT deliberately does NOT fail the run: it is not yet known to
    # be a defect, and a red exit is pressure to make it go away -- which here
    # means routing an ABI difference to Track A as a codegen bug. It is loud in
    # the report instead, which is where an unresolved thing belongs.
    return 1 if ("MISCOMPILE_VS_GCC" in counts or "MISCOMPILE_OPT" in counts) else 0


if __name__ == "__main__":
    sys.exit(main())
