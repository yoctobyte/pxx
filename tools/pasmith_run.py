#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""pasmith_run -- differential driver for tools/pasmith.py.

See devdocs/progress/backlog/feature-pasmith-pascal-program-generator.md.

Generates random well-defined Pascal programs (pasmith.py), compiles each with
several independent "oracles", runs them, and compares the single checksum each
one prints. Any disagreement is a bug in somebody; the oracle set is chosen so
that WHICH somebody is usually mechanical rather than a judgement call:

  fpc-O0, fpc-O2      FPC, the external reference implementation. This is the
                      oracle tools/fuzz.sh structurally cannot have: a bug in
                      SHARED IR lowering produces the same wrong answer on all
                      of pxx's targets, they all agree, and the divergence is
                      invisible. An independent implementation sees it.
  pxx-O0/-O2/-O3      pxx against itself at different optimisation levels.
                      Needs no FPC at all; catches optimiser bugs (Track O).
  i386/aarch64/...    pxx cross-targets under QEMU (the fuzz.sh oracle),
                      catching backend-divergent codegen bugs.

Triage, per the ticket: the prior favours "pasmith emitted something it
shouldn't have", so that is where you LOOK FIRST -- it is not a verdict. A
fuzzer deliberately samples the tail of the language that nobody has written
before, which is exactly where FPC's own coverage is thinnest, so a real FPC
bug is an expected and welcome outcome, not something to explain away. Two
cases need no judgement at all and are labelled as such below:

  fpc-O0 != fpc-O2    FPC contradicts ITSELF. pxx is not even in the room.
  pxx-O0 != pxx-O2/3  pxx contradicts itself. FPC is not in the room.

Usage:
  tools/pasmith_run.py --minutes 5
  tools/pasmith_run.py --seeds 1-200 --cross      # add QEMU cross-targets
  tools/pasmith_run.py --seed 12345 --shrink-only # re-shrink one finding
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PXX = os.environ.get("PXX_STABLE", os.path.join(ROOT, "stable_linux_amd64", "default", "pinned"))
RTL = os.path.join(ROOT, "lib", "rtl")
PASMITH = os.path.join(ROOT, "tools", "pasmith.py")
RUN_TARGET = os.path.join(ROOT, "tools", "run_target.sh")
FINDINGS = os.environ.get("PASMITH_FINDINGS_DIR", "/tmp/pxx_pasmith_findings")
RUN_TIMEOUT = 10
COMPILE_TIMEOUT = 120

CROSS_ARCHS = ["i386", "aarch64", "arm32"]

# Result sentinels, kept distinct from any real checksum so they can never
# silently compare equal to one.
COMPILE_FAIL = "<compile-fail>"
TIMEOUT = "<timeout>"
CRASH = "<crash>"


class Oracle:
    def __init__(self, name, kind, args=(), arch=None):
        self.name = name
        self.kind = kind      # "fpc" | "pxx"
        self.args = list(args)
        self.arch = arch


def build_oracles(cross):
    o = [
        Oracle("fpc-O0", "fpc", ["-O-"]),
        Oracle("fpc-O2", "fpc", ["-O2"]),
        Oracle("pxx-O0", "pxx", []),
        Oracle("pxx-O2", "pxx", ["-O2"]),
        Oracle("pxx-O3", "pxx", ["-O3"]),
    ]
    if cross:
        for a in CROSS_ARCHS:
            o.append(Oracle("pxx-%s" % a, "pxx", ["--target=%s" % a], arch=a))
    return o


def run(cmd, timeout, cwd=None):
    try:
        p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return 124, ""
    except OSError as e:
        return 127, str(e)


def evaluate(oracle, src, workdir):
    """Compile + run `src` under one oracle. Returns its checksum, or a sentinel."""
    out = os.path.join(workdir, "b_" + oracle.name.replace("/", "_"))
    if oracle.kind == "fpc":
        cmd = ["fpc", "-Mobjfpc", "-vw"] + oracle.args + ["-o" + out, src]
    else:
        cmd = [PXX, "-Fu" + RTL] + oracle.args + [src, out]
    rc, _ = run(cmd, COMPILE_TIMEOUT, cwd=workdir)
    if rc != 0 or not os.path.exists(out):
        return COMPILE_FAIL

    if oracle.arch:
        rc, txt = run([RUN_TARGET, oracle.arch, out], RUN_TIMEOUT)
    else:
        rc, txt = run([out], RUN_TIMEOUT)
    if rc == 124:
        return TIMEOUT
    if rc != 0:
        return "%s(rc=%d)" % (CRASH, rc)
    return txt.strip()


def classify(results):
    """Group oracle results by value. Returns (diverged?, groups, note)."""
    groups = {}
    for name, val in results.items():
        groups.setdefault(val, []).append(name)

    # A program FPC cannot compile is a pasmith bug (its contract is to emit
    # only valid objfpc), and we cannot judge pxx against a broken oracle --
    # so report it as its own class, loudly, rather than as a "divergence".
    if any(results.get(n) == COMPILE_FAIL for n in ("fpc-O0", "fpc-O2")):
        return True, groups, "FPC REJECTED THE PROGRAM -- pasmith contract violation (see ticket triage)"

    real = {k: v for k, v in groups.items() if k != COMPILE_FAIL}
    if len(real) <= 1:
        return False, groups, ""

    note = ""
    f0, f2 = results.get("fpc-O0"), results.get("fpc-O2")
    if f0 is not None and f2 is not None and f0 != f2:
        note = "FPC CONTRADICTS ITSELF (-O0 vs -O2) -- an FPC bug, no judgement needed; pxx is not involved"
    pxxv = {k: v for k, v in results.items() if k.startswith("pxx-O")}
    if len(set(pxxv.values())) > 1:
        note = (note + " | " if note else "") + \
            "pxx CONTRADICTS ITSELF across -O levels -- an optimiser bug (Track A/O); FPC not involved"
    if not note:
        fpcv = {v for k, v in results.items() if k.startswith("fpc")}
        pv = {v for k, v in results.items() if k.startswith("pxx")}
        if len(fpcv) == 1 and len(pv) == 1:
            note = ("pxx and FPC each self-consistent but disagree -- investigate in order: "
                    "(a) pasmith emitted UB/impl-defined code, (b) pxx bug, (c) FPC bug. "
                    "Do NOT auto-dismiss (c).")
    return True, groups, note


def diverges(src, workdir, oracles, baseline_note):
    res = {o.name: evaluate(o, src, workdir) for o in oracles}
    bad, groups, note = classify(res)
    # During shrinking we require the SAME kind of divergence, not just any --
    # otherwise the shrinker happily "reduces" a codegen bug into an unrelated
    # compile error and the reproducer proves nothing.
    if bad and note == baseline_note:
        return True, res, note
    return False, res, note


def shrink(src_path, workdir, oracles, note, max_passes=8):
    """Greedy line-wise delta debug, gated on the divergence still reproducing.

    Deleting a line usually breaks syntax; that candidate simply fails to
    reproduce (FPC won't compile it) and is rejected. Crude, but it is a
    generated program -- most of it is dead weight, and cutting 90% of the
    lines is what makes a finding a filable ticket instead of a wall of text.
    """
    with open(src_path) as f:
        lines = f.read().split("\n")
    cand_path = os.path.join(workdir, "shrink.pas")

    def repro(ls):
        with open(cand_path, "w") as f:
            f.write("\n".join(ls))
        ok, _, _ = diverges(cand_path, workdir, oracles, note)
        return ok

    for _ in range(max_passes):
        progress = False
        i = 0
        while i < len(lines):
            ln = lines[i].strip()
            # Never delete the structural skeleton -- doing so can only ever
            # produce a non-compiling candidate, so it wastes a compile.
            if (ln.startswith("program ") or ln.startswith("{$") or ln == "begin"
                    or ln in ("end.", "end;", "end") or ln.startswith("writeln")):
                i += 1
                continue
            trial = lines[:i] + lines[i + 1:]
            if repro(trial):
                lines = trial
                progress = True
            else:
                i += 1
        if not progress:
            break
    return "\n".join(lines)


def parse_seeds(spec):
    if "-" in spec:
        a, b = spec.split("-", 1)
        return list(range(int(a), int(b) + 1))
    return [int(spec)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--minutes", type=float, default=2.0)
    ap.add_argument("--seeds", help="explicit seed range, e.g. 1-500 (overrides --minutes)")
    ap.add_argument("--seed", type=int, help="single seed")
    ap.add_argument("--cross", action="store_true", help="also run pxx cross-targets under QEMU")
    ap.add_argument("--no-shrink", action="store_true")
    ap.add_argument("--start", type=int, default=1, help="first seed for the timed loop")
    ap.add_argument("--vars", type=int, default=8)
    ap.add_argument("--funcs", type=int, default=3)
    ap.add_argument("--stmts", type=int, default=12)
    ap.add_argument("--depth", type=int, default=3)
    a = ap.parse_args()

    if not os.path.exists(PXX):
        print("no stable compiler at %s" % PXX, file=sys.stderr)
        return 2
    if not shutil.which("fpc"):
        print("fpc not found -- the external oracle is the point of this tool", file=sys.stderr)
        return 2

    oracles = build_oracles(a.cross)
    os.makedirs(FINDINGS, exist_ok=True)
    workdir = tempfile.mkdtemp(prefix="pasmith.")

    if a.seed is not None:
        seeds = [a.seed]
    elif a.seeds:
        seeds = parse_seeds(a.seeds)
    else:
        seeds = None   # timed loop

    print("pasmith_run: oracles=[%s] findings->%s" % (
        ", ".join(o.name for o in oracles), FINDINGS))

    deadline = time.time() + a.minutes * 60
    n = found = fpc_reject = 0
    seed = a.start
    try:
        while True:
            if seeds is not None:
                if n >= len(seeds):
                    break
                seed = seeds[n]
            elif time.time() >= deadline:
                break
            n += 1

            src = os.path.join(workdir, "p%d.pas" % seed)
            rc, out = run([sys.executable, PASMITH, "--seed", str(seed),
                           "--vars", str(a.vars), "--funcs", str(a.funcs),
                           "--stmts", str(a.stmts), "--depth", str(a.depth),
                           "-o", src], 60)
            if rc != 0:
                print("GENERATOR FAILED seed=%d: %s" % (seed, out))
                seed += 1
                continue

            res = {o.name: evaluate(o, src, workdir) for o in oracles}
            bad, groups, note = classify(res)
            if not bad:
                seed += 1
                continue

            found += 1
            if "REJECTED" in note:
                fpc_reject += 1
            print("\n=== DIVERGENCE  seed=%d" % seed)
            print("    %s" % note)
            for val, names in sorted(groups.items(), key=lambda kv: -len(kv[1])):
                print("    %-40s : %s" % (",".join(sorted(names)), val))

            stem = os.path.join(FINDINGS, "seed_%d" % seed)
            shutil.copy(src, stem + ".pas")
            if not a.no_shrink:
                print("    shrinking...")
                small = shrink(src, workdir, oracles, note)
                with open(stem + ".min.pas", "w") as f:
                    f.write(small)
                nl = len([x for x in small.split("\n") if x.strip()])
                print("    shrunk to %d lines -> %s.min.pas" % (nl, stem))
            with open(stem + ".txt", "w") as f:
                f.write("seed=%d\nnote=%s\n\n" % (seed, note))
                for k, v in sorted(res.items()):
                    f.write("%-12s %s\n" % (k, v))
            seed += 1
    except KeyboardInterrupt:
        print("\ninterrupted")

    print("\npasmith_run: %d programs, %d divergences (%d = FPC-rejected/generator bugs)"
          % (n, found, fpc_reject))
    # A clean run is a VALID, useful result (same inverted-success-criteria as
    # feature-ir-fuzzer), not a failure -- so exit 0 either way; the caller
    # reads the count.
    return 0


if __name__ == "__main__":
    sys.exit(main())
