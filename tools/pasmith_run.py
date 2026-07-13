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
  tools/pasmith_run.py --seed 12345               # re-run one seed (it IS the repro)
"""

import argparse
import os
import re
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
# Everything is bounded. A generated program terminates by construction, so a
# run that hits the timeout is itself a finding, never a reason to wait longer.
RUN_TIMEOUT = 5
COMPILE_TIMEOUT = 30

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


def localize(src, workdir, oracles, groups):
    """Point at the STATEMENT that first diverged -- without deleting anything.

    This replaces a delta-debugging shrinker, deliberately. Shrinking exists in
    Csmith because its reproducers go to strangers who will not read 40KB. Ours
    go to an agent in this repo, and the program is SEEDED: `--seed N` already
    is the reproducer, permanently and for free, at any size. Reducing the
    source buys nothing here -- and the pressure to reduce it pushes toward
    generating SMALL programs, which is precisely backwards. Small programs make
    the fuzzer's job easy and the compiler's job easy; the whole point is the
    opposite. Deep inheritance chains, ctor/dtor ordering and vtable dispatch do
    not even begin to strain a compiler until programs are LARGE.

    So instead of cutting code down, we ask the program where it went wrong.
    pasmith --trace emits the running checksum after every statement rather than
    only at exit. Run the same program under two oracles, diff the two traces,
    and the FIRST differing checkpoint is the guilty statement -- located
    exactly, in one run per oracle, on a program of any size. Cost is O(1)
    compiles instead of O(lines), and it gets BETTER with bigger programs
    instead of collapsing.
    """
    names = sorted(groups.items(), key=lambda kv: -len(kv[1]))
    if len(names) < 2:
        return None
    a_name = sorted(names[0][1])[0]
    b_name = sorted(names[1][1])[0]
    by = {o.name: o for o in oracles}
    if a_name not in by or b_name not in by:
        return None

    # Rebuild the SAME program in trace mode. The seed plus the gen-args
    # recorded in the source header reproduce it byte-for-byte, so no state
    # needs to be threaded here -- the source is self-describing.
    traced = os.path.join(workdir, "traced.pas")
    rc, _ = run([sys.executable, PASMITH, "--seed", str(seed_of(src)),
                 "--trace", "-o", traced] + gen_args_of(src), 60)
    if rc != 0:
        return None

    ta = evaluate(by[a_name], traced, workdir)
    tb = evaluate(by[b_name], traced, workdir)
    la, lb = ta.split("\n"), tb.split("\n")
    for i in range(min(len(la), len(lb))):
        if la[i] != lb[i]:
            return ("first divergence at checkpoint %d of %d\n"
                    "    %-10s %s\n    %-10s %s\n"
                    "    (checkpoint N = the Nth statement of the traced program;\n"
                    "     everything before it agrees, so the bug is AT that statement)"
                    % (i + 1, min(len(la), len(lb)), a_name, la[i], b_name, lb[i]))
    return "traces agree up to the shorter one (%d vs %d checkpoints)" % (len(la), len(lb))


# The traced rebuild has to reproduce the SAME program, so the generation
# parameters travel with the source rather than being guessed.
def seed_of(src_path):
    with open(src_path) as f:
        for line in f:
            m = re.search(r"seed (\d+)", line)
            if m:
                return int(m.group(1))
    return 0


def gen_args_of(src_path):
    with open(src_path) as f:
        head = f.read(2000)
    m = re.search(r"gen-args:([^}\n]*)", head)
    return m.group(1).split() if m else []


def check(nseeds, args):
    """The GENERATOR's own gate: does FPC accept everything pasmith emits?

    This is the tool's test, and it is deliberately cheap: compile only, never
    run, one oracle, no shrinking, no iteration. pasmith's contract is "emits
    valid, well-typed objfpc" -- FPC accepting the program IS that contract,
    and it is a syntax/semantics question, so a compile answers it in full.
    Anything FPC rejects is a generator bug, full stop (a compiler can't be
    'wrong' about code we promised would be valid), so this needs none of the
    differential machinery and none of its cost.

    Run this after touching pasmith.py. Divergence hunting is a separate,
    slower activity -- do not conflate them.
    """
    workdir = tempfile.mkdtemp(prefix="pasmith-check.")
    fpc = Oracle("fpc-O0", "fpc", ["-O-"])
    bad = []
    t0 = time.time()
    for seed in range(1, nseeds + 1):
        src = os.path.join(workdir, "c%d.pas" % seed)
        rc, out = run([sys.executable, PASMITH, "--seed", str(seed),
                       "--vars", str(args.vars), "--funcs", str(args.funcs),
                       "--stmts", str(args.stmts), "--depth", str(args.depth),
                       "--classes", str(args.classes), "--objs", str(args.objs),
                       "--strs", str(args.strs), "-o", src], 60)
        if rc != 0:
            bad.append((seed, "generator crashed: %s" % out.strip()[:120]))
            continue
        outbin = os.path.join(workdir, "c%d" % seed)
        rc, txt = run(["fpc", "-Mobjfpc", "-vw", "-O-", "-o" + outbin, src],
                      COMPILE_TIMEOUT, cwd=workdir)
        if rc != 0:
            errs = [l for l in txt.split("\n") if "Error:" in l or "Fatal:" in l]
            bad.append((seed, errs[0].strip() if errs else "fpc rc=%d" % rc))
            shutil.copy(src, os.path.join(FINDINGS, "reject_seed_%d.pas" % seed))
    dt = time.time() - t0

    print("pasmith --check: %d seeds, %d rejected by FPC  (%.1fs)"
          % (nseeds, len(bad), dt))
    for seed, why in bad[:10]:
        print("  seed %-5d %s" % (seed, why))
    if bad:
        print("\nFPC rejecting pasmith output is a GENERATOR bug -- pasmith's whole")
        print("contract is that it emits valid objfpc. Fix pasmith, not the compiler.")
        print("Rejected sources saved to %s/reject_seed_*.pas" % FINDINGS)
        return 1
    return 0


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
    ap.add_argument("--check", type=int, metavar="N", nargs="?", const=50,
                    help="GENERATOR GATE: compile N seeds with FPC only (no run, no "
                         "oracles). FPC must accept 100%%; anything else is a pasmith "
                         "bug. Fast, non-iterative. Run after touching pasmith.py.")
    ap.add_argument("--no-localize", action="store_true",
                    help="skip the trace-diff that names the diverging statement")
    ap.add_argument("--start", type=int, default=1, help="first seed for the timed loop")
    ap.add_argument("--vars", type=int, default=8)
    ap.add_argument("--funcs", type=int, default=3)
    ap.add_argument("--stmts", type=int, default=12)
    ap.add_argument("--depth", type=int, default=3)
    ap.add_argument("--classes", type=int, default=0)
    ap.add_argument("--objs", type=int, default=3)
    ap.add_argument("--strs", type=int, default=0)
    a = ap.parse_args()

    if not os.path.exists(PXX):
        print("no stable compiler at %s" % PXX, file=sys.stderr)
        return 2
    if not shutil.which("fpc"):
        print("fpc not found -- the external oracle is the point of this tool", file=sys.stderr)
        return 2

    os.makedirs(FINDINGS, exist_ok=True)
    if a.check is not None:
        return check(a.check, a)

    oracles = build_oracles(a.cross)
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
                           "--classes", str(a.classes), "--objs", str(a.objs),
                           "--strs", str(a.strs), "-o", src], 60)
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
            loc = None
            if not a.no_localize and "REJECTED" not in note:
                loc = localize(src, workdir, oracles, groups)
                if loc:
                    print("    %s" % loc.replace("\n", "\n    "))
            with open(stem + ".txt", "w") as f:
                f.write("seed=%d\nnote=%s\n\n" % (seed, note))
                for k, v in sorted(res.items()):
                    f.write("%-12s %s\n" % (k, v))
                if loc:
                    f.write("\n%s\n" % loc)
                f.write("\nrepro: tools/pasmith.py --seed %d --vars %d --funcs %d "
                        "--stmts %d --depth %d\n" % (seed, a.vars, a.funcs, a.stmts, a.depth))
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
