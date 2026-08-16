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

Buckets, worst first:
  MISCOMPILE_VS_GCC   pxx and gcc both ran and printed DIFFERENT checksums
  MISCOMPILE_OPT      two pxx -O levels printed different checksums
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


SKIP = "skip"   # the seed told us nothing (gcc could not build or run it)


def fuzz_one(seed, inc, pxx, opts, timeout, workdir, csmith_args):
    src = workdir / "t.c"
    rc, out, _ = run(["csmith", "--seed", str(seed), "--output", str(src)] + csmith_args, 120)
    if rc != 0 or not src.is_file():
        return SKIP  # generator hiccup

    # ---- the oracle -------------------------------------------------------
    gcc_bin = workdir / "g"
    rc, out, _ = run(["gcc", "-O0", f"-I{inc}", "-w", str(src), "-o", str(gcc_bin)], 180)
    if rc != 0:
        return SKIP  # gcc won't build it -> not our problem
    rc, gcc_out, gcc_sec = run([str(gcc_bin)], timeout)
    if rc != 0 or "checksum" not in gcc_out:
        return SKIP  # gcc's own binary misbehaved or hung

    # Now that the oracle's cost is known, give pxx a budget proportional to it
    # rather than the flat one that misfiled seed 90044 as a hang.
    run_limit = max(timeout, TIMEOUT_FACTOR * gcc_sec)

    # ---- pxx, at each -O level -------------------------------------------
    results, secs = {}, {}
    for opt in opts:
        pbin = workdir / f"p{opt}"
        cmd = [str(pxx)]
        if opt != "default":
            cmd.append(f"-O{opt}")
        cmd += [f"-I{inc}", str(src), str(pbin)]   # pxx wants -Ipath joined, not -I path
        rc, cout, _ = run(cmd, 300)
        if rc != 0:
            return Finding("PXX_COMPILE_FAIL", seed,
                           f"-O{opt}\n{cout}", f"O{opt}:{first_error_line(cout)}")

        rc, rout, sec = run([str(pbin)], run_limit)
        if rc is None:
            return Finding("PXX_TIMEOUT", seed,
                           f"-O{opt} did not finish in {run_limit:.1f}s "
                           f"({TIMEOUT_FACTOR}x the gcc oracle's {gcc_sec:.1f}s)",
                           f"O{opt}:timeout")
        if rc != 0 or "checksum" not in rout:
            return Finding("PXX_CRASH", seed,
                           f"-O{opt} exit={rc}\n{rout}", f"O{opt}:exit{rc}")
        results[opt] = rout.strip()
        secs[opt] = sec

    # ---- compare ----------------------------------------------------------
    gcc_sum = gcc_out.strip()
    for opt, got in results.items():
        if got != gcc_sum:
            return Finding("MISCOMPILE_VS_GCC", seed,
                           f"-O{opt}\n  gcc: {gcc_sum}\n  pxx: {got}",
                           f"O{opt}:vs-gcc")

    distinct = set(results.values())
    if len(distinct) > 1:
        detail = "\n".join(f"  -O{o}: {v}" for o, v in sorted(results.items()))
        return Finding("MISCOMPILE_OPT", seed, "pxx disagrees with itself:\n" + detail,
                       "opt-levels-disagree")

    # Only now, with every checksum agreeing, is "slow" the interesting fact.
    # Deliberately after the comparisons: a wrong answer beats a slow one, and a
    # miscompile must never be filed as a performance note.
    slow = {o: s for o, s in secs.items()
            if s >= SLOW_MIN_SEC and gcc_sec > 0 and s > SLOW_FACTOR * gcc_sec}
    if slow:
        detail = "\n".join(f"  -O{o}: {s:.1f}s  ({s / gcc_sec:.1f}x)"
                           for o, s in sorted(slow.items()))
        worst = max(slow, key=slow.get)
        return Finding("PXX_SLOW", seed,
                       f"finished and AGREED with gcc, but slow.\n"
                       f"  gcc -O0: {gcc_sec:.1f}s\n{detail}\n\n"
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

    print(f"csmith fuzz: {len(seeds)} program(s), pxx -O{{{','.join(opts)}}} vs gcc -O0 oracle")
    print(f"  csmith.h: {inc}")
    print(f"  findings: {outdir}")

    seen = {}          # dedup key -> first seed that showed it
    counts = {}
    skipped = 0
    agreed = 0
    workdir = Path(tempfile.mkdtemp(prefix="csmith-fuzz-"))
    try:
        for i, seed in enumerate(seeds, 1):
            f = fuzz_one(seed, inc, pxx, opts, args.timeout, workdir, csmith_args)
            if f is SKIP:
                skipped += 1
                print(f"  [{i}/{len(seeds)}] seed {seed}: skip (gcc could not build/run it)",
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
                f"gcc -O0 -w -I{inc} t.c -o t_gcc && ./t_gcc\n"
                f"{pxx} -I{inc} t.c t_pxx && ./t_pxx\n```\n\n"
                f"Or: `tools/csmith_fuzz.py --seed {seed}`\n")
            print(f"  [{i}/{len(seeds)}] seed {seed}: *** {f.bucket} *** -> {d}", flush=True)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print()
    print("== csmith fuzz report ==")
    print(f"  {agreed}/{len(seeds)} agreed with the gcc oracle"
          + (f"  ({skipped} skipped)" if skipped else ""))
    if not counts:
        print("  no findings")
        return 0
    for bucket in ("MISCOMPILE_VS_GCC", "MISCOMPILE_OPT", "PXX_CRASH",
                   "PXX_COMPILE_FAIL", "PXX_TIMEOUT", "PXX_SLOW"):
        if bucket in counts:
            uniq = sum(1 for k in seen if k.startswith(bucket + "|"))
            print(f"  {bucket:20s} {counts[bucket]:4d} hit(s), {uniq} distinct")
    print(f"\n  saved to {outdir}")
    # a miscompile is a hard failure; gaps and crashes are findings to triage
    return 1 if ("MISCOMPILE_VS_GCC" in counts or "MISCOMPILE_OPT" in counts) else 0


if __name__ == "__main__":
    sys.exit(main())
