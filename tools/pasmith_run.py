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
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _pick_compiler():
    """Fuzz the compiler AT THIS COMMIT, not the pinned stable.

    Defaulting to PXX_STABLE (the committed pinned binary) meant the fuzzer was
    testing a compiler from potentially hundreds of commits ago, while stamping
    every finding with the sha under test. Two consequences, both bad:

      * findings are misattributed -- the bug is not in that sha, it is in
        whatever the pin was built from;
      * an ALREADY-FIXED bug keeps re-reporting forever, until someone happens to
        re-pin. That is exactly what happened: all ~70 published divergences were
        the `case`-selector bug (b346), which Track A had already fixed at HEAD --
        the fuzzer kept finding it because the pinned binary still had it.

    So prefer the locally built compiler/pascal26 (what testmgr built at this
    sha); fall back to the pin only if there is no local build. PXX_STABLE still
    overrides, for deliberately fuzzing the pin.
    """
    env = os.environ.get("PXX_STABLE")
    if env:
        return env
    built = os.path.join(ROOT, "compiler", "pascal26")
    if os.path.exists(built):
        return built
    return os.path.join(ROOT, "stable_linux_amd64", "default", "pinned")


PXX = _pick_compiler()
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


LAST_ERR = {}       # oracle name -> slug of its most recent compile diagnostic


def error_slug(txt):
    """A short, stable slug for a compile diagnostic: the deduplication key for a
    rejected program. Line numbers, paths and the offending token vary per seed and
    are stripped -- what is left is WHICH error, which is what a signature wants."""
    line = ""
    for l in (txt or "").split("\n"):
        if "error:" in l.lower() or "fatal:" in l.lower():
            line = l.split("rror:", 1)[-1].split("atal:", 1)[-1]
            break
    line = re.sub(r"[^a-zA-Z ]+", " ", line).strip().lower()
    words = [w for w in line.split() if len(w) > 2][:4]
    return "-".join(words) or "compile-fail"


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
    rc, txt = run(cmd, COMPILE_TIMEOUT, cwd=workdir)
    if rc != 0 or not os.path.exists(out):
        # Keep the diagnostic: it is the SIGNATURE of a compile failure. Two
        # different rejections are two different bugs, and without the message they
        # would dedupe into one indistinguishable "pxx-reject" bucket.
        LAST_ERR[oracle.name] = error_slug(txt)
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
    """Group oracle results by value. Returns (diverged?, groups, note, cls).

    `cls` is the coarse KIND of disagreement -- who contradicts whom. It is half
    of a finding's signature (the other half is the statement it sits on), and
    the signature is what stops one bug from being reported five hundred times.
    """
    groups = {}
    for name, val in results.items():
        groups.setdefault(val, []).append(name)

    # A program FPC cannot compile is a pasmith bug (its contract is to emit
    # only valid objfpc), and we cannot judge pxx against a broken oracle --
    # so report it as its own class, loudly, rather than as a "divergence".
    if any(results.get(n) == COMPILE_FAIL for n in ("fpc-O0", "fpc-O2")):
        return (True, groups,
                "FPC REJECTED THE PROGRAM -- pasmith contract violation (see ticket triage)",
                "fpc-reject")

    # pxx failing to compile a program FPC accepts is a REAL finding (a frontend
    # gap or regression), not a non-event. It used to vanish silently: the
    # COMPILE_FAIL group was filtered out and the remaining oracles all agreed,
    # so the program was scored clean. A compiler that cannot build valid objfpc
    # is exactly what this tool exists to catch.
    if any(v == COMPILE_FAIL for k, v in results.items() if k.startswith("pxx")):
        return (True, groups,
                "pxx REJECTED a program FPC accepts -- frontend gap or regression (Track A/P)",
                "pxx-reject")

    for k, v in results.items():
        if k.startswith("pxx") and (v == TIMEOUT or v.startswith(CRASH)):
            return (True, groups,
                    "pxx-built binary crashed or hung (%s) -- generated programs terminate "
                    "by construction, so this is never the program's fault" % v,
                    "pxx-" + ("timeout" if v == TIMEOUT else "crash"))

    real = {k: v for k, v in groups.items() if k != COMPILE_FAIL}
    if len(real) <= 1:
        return False, groups, "", ""

    note, cls = "", "unknown"
    f0, f2 = results.get("fpc-O0"), results.get("fpc-O2")
    if f0 is not None and f2 is not None and f0 != f2:
        note = "FPC CONTRADICTS ITSELF (-O0 vs -O2) -- an FPC bug, no judgement needed; pxx is not involved"
        cls = "fpc-self"
    pxxv = {k: v for k, v in results.items() if k.startswith("pxx-O")}
    if len(set(pxxv.values())) > 1:
        note = (note + " | " if note else "") + \
            "pxx CONTRADICTS ITSELF across -O levels -- an optimiser bug (Track A/O); FPC not involved"
        cls = "pxx-self" if cls == "unknown" else cls + "+pxx-self"
    arch = {k: v for k, v in results.items()
            if k.startswith("pxx-") and not k.startswith("pxx-O")}
    if arch and len(set(list(arch.values()) + [results.get("pxx-O0")])) > 1:
        note = (note + " | " if note else "") + \
            "pxx TARGETS DISAGREE -- a backend codegen bug (Track A); FPC not involved"
        cls = "pxx-cross" if cls == "unknown" else cls
    if cls == "unknown":
        fpcv = {v for k, v in results.items() if k.startswith("fpc")}
        pv = {v for k, v in results.items() if k.startswith("pxx")}
        if len(fpcv) == 1 and len(pv) == 1:
            note = ("pxx and FPC each self-consistent but disagree -- investigate in order: "
                    "(a) pasmith emitted UB/impl-defined code, (b) pxx bug, (c) FPC bug. "
                    "Do NOT auto-dismiss (c).")
            cls = "pxx-vs-fpc"
    return True, groups, note, cls


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

    Returns (text, kind): the human-readable localisation, and the KIND of the
    guilty statement (`case`, `virtcall`, `strassign`, ...), which pasmith stamps
    into each checkpoint comment. The kind is the deduplication key -- see
    signature().
    """
    names = sorted(groups.items(), key=lambda kv: -len(kv[1]))
    if len(names) < 2:
        return None, None
    a_name = sorted(names[0][1])[0]
    b_name = sorted(names[1][1])[0]
    by = {o.name: o for o in oracles}
    if a_name not in by or b_name not in by:
        return None, None

    # Rebuild the SAME program in trace mode. The seed plus the gen-args
    # recorded in the source header reproduce it byte-for-byte, so no state
    # needs to be threaded here -- the source is self-describing.
    traced = os.path.join(workdir, "traced.pas")
    rc, _ = run([sys.executable, PASMITH, "--seed", str(seed_of(src)),
                 "--trace", "-o", traced] + gen_args_of(src), 60)
    if rc != 0:
        return None, None
    kinds = checkpoint_kinds(traced)

    ta = evaluate(by[a_name], traced, workdir)
    tb = evaluate(by[b_name], traced, workdir)
    la, lb = ta.split("\n"), tb.split("\n")
    for i in range(min(len(la), len(lb))):
        if la[i] != lb[i]:
            kind = kinds[i] if i < len(kinds) else "?"
            return ("first divergence at checkpoint %d of %d -- a `%s` statement\n"
                    "    %-10s %s\n    %-10s %s\n"
                    "    (checkpoint N = the Nth statement of the traced program;\n"
                    "     everything before it agrees, so the bug is AT that statement)"
                    % (i + 1, min(len(la), len(lb)), kind,
                       a_name, la[i], b_name, lb[i]), kind)
    return ("traces agree up to the shorter one (%d vs %d checkpoints)"
            % (len(la), len(lb)), "trace-length")


def checkpoint_kinds(traced_src):
    """The statement kind behind each trace checkpoint, in order."""
    with open(traced_src) as f:
        return re.findall(r"\{ checkpoint \d+ kind=(\S+) \}", f.read())


# --- the findings ledger ---------------------------------------------------
# The problem it solves, concretely: one `case`-selector defect produced 639
# published reports. Every one of them was the same bug, and the pile buried the
# question that actually matters -- how many DISTINCT causes has this fuzzer
# found? (The ticket puts it as "a fuzzer that reports one bug 527 times is not
# finding bugs; it is finding *a* bug, loudly.")
#
# So a finding gets a SIGNATURE, and the ledger holds one entry per signature:
#
#     signature = <who-disagrees> _ <what-statement-it-sits-on>
#                 e.g.  pxx-vs-fpc_case      pxx-self_virtcall
#
# Coarse ON PURPOSE. A finer key (the statement's operators, a hash of its text)
# would have split those 639 reports right back into hundreds of "distinct"
# signatures, because the surrounding expression differs every seed -- which is
# the failure mode we are removing, dressed up as precision. Coarse costs us the
# ability to distinguish two simultaneous bugs in the same construct; the ledger
# keeps up to EXAMPLES_PER_SIG example seeds per entry so a triager still has
# varied material to look at, and a second bug in `case` surfaces the moment the
# first is fixed and the entry reopens.
#
# The ledger is the rate limiter, too. A known-open signature is COUNTED, never
# re-filed; a NEW signature stops the run (--stop-on-new) so it can be filed and
# handed to the owning lane. twatch then throttles further fuzzing while anything
# is open, rechecks the open entries at each new sha, and goes back to full speed
# by itself once they stop reproducing (--recheck). Fuzzing resumes on the FIX,
# not on a human remembering to re-enable it.

LEDGER_VERSION = 1
EXAMPLES_PER_SIG = 5


def signature(cls, kind):
    return "%s_%s" % (cls or "unknown", kind or "unknown")


def load_ledger(path):
    try:
        with open(path) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return {"version": LEDGER_VERSION, "findings": {}}
    d.setdefault("findings", {})
    return d


def save_ledger(led, path):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(led, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def ledger_open(led):
    """The findings that THROTTLE fuzzing.

    Four statuses, and the distinction that matters is not "fixed or not", it is
    "can the fuzzer still trip over it":

      open      found, not yet triaged            -> throttles
      ticketed  filed into the owning lane, unfixed, and the generator can STILL
                emit the shape                    -> throttles
      dodged    filed, unfixed, but the generator AVOIDS the shape by construction
                (a NO_* constant in pasmith.py)   -> does NOT throttle
      fixed     its example seeds no longer reproduce -> does not throttle

    `dodged` is the honest answer to "why are we slowing down?". Throttling exists so
    the fuzzer stops re-deriving a bug that is already on somebody's desk. Once the
    generator refuses to emit the shape at all, it CANNOT re-derive it -- so slowing
    down buys nothing and costs every other bug we would have found meanwhile. The
    ticket, not the throttle, is what tracks the fix; when it lands, flip the NO_*
    constant back and the entry with it.
    """
    return {s: e for s, e in led["findings"].items()
            if e.get("status") in ("open", "ticketed")}


def ledger_record(led, sig, cls, kind, seed, gen_args, note, sha):
    """Fold one divergence into the ledger. Returns True if the SIGNATURE is new
    (or has reopened after being marked fixed) -- i.e. if this is news."""
    e = led["findings"].get(sig)
    now = utcnow()
    if e is None or e.get("status") == "fixed":
        reopened = e is not None
        led["findings"][sig] = {
            "sig": sig, "class": cls, "kind": kind, "status": "open",
            "opened": now, "first_seed": seed, "first_sha": sha,
            "examples": [{"seed": seed, "args": gen_args, "sha": sha}],
            "hits": 1, "note": note, "ticket": None,
            "reopened_from_fixed": reopened,
        }
        return True
    e["hits"] = e.get("hits", 0) + 1
    e["last_seen"] = now
    ex = e.setdefault("examples", [])
    if len(ex) < EXAMPLES_PER_SIG and all(x["seed"] != seed for x in ex):
        ex.append({"seed": seed, "args": gen_args, "sha": sha})
    return False


def recheck(led, oracles, workdir, sha=None):
    """Re-run every open signature's example seeds against the CURRENT compiler.

    An entry whose examples all agree now is marked fixed, and fuzzing goes back
    to full speed on the next tick. This is the half of the rate limiter that
    lets go: throttling on an open finding is only acceptable if something
    notices, unprompted, that it has been fixed. Nobody has to remember to
    re-enable the fuzzer.

    Returns (n_fixed, n_still_open).
    """
    fixed = still = 0
    for sig, e in sorted(ledger_open(led).items()):
        reproduces = False
        for ex in e.get("examples", []):
            src = os.path.join(workdir, "recheck_%d.pas" % ex["seed"])
            rc, _ = run([sys.executable, PASMITH] + ex["args"] + ["-o", src], 60)
            if rc != 0:
                reproduces = True      # cannot judge: keep it open, loudly
                break
            res = {o.name: evaluate(o, src, workdir) for o in oracles}
            bad, _, _, cls = classify(res)
            if bad:
                reproduces = True
                break
        if reproduces:
            still += 1
            print("  %-28s still reproduces" % sig)
        else:
            e["status"] = "fixed"
            e["fixed"] = utcnow()
            e["fixed_sha"] = sha or ""
            fixed += 1
            print("  %-28s FIXED (%d example seed(s) now agree)"
                  % (sig, len(e.get("examples", []))))
    return fixed, still


def ledger_status(led):
    fs = led["findings"]
    if not fs:
        print("ledger: empty -- no findings recorded")
        return 0
    print("%-28s %-7s %6s  %-20s %s" % ("SIGNATURE", "STATUS", "HITS", "OPENED", "TICKET"))
    for sig, e in sorted(fs.items()):
        print("%-28s %-7s %6d  %-20s %s"
              % (sig, e.get("status", "?"), e.get("hits", 0),
                 (e.get("opened") or "")[:19], e.get("ticket") or "-"))
    n_open = len(ledger_open(led))
    print("\n%d finding(s), %d open. Fuzzing is throttled while any are open; each "
          "is rechecked\nat every new sha and reopens the tap by itself once it stops "
          "reproducing." % (len(fs), n_open))
    return 0


def utcnow():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


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
        rc, out = run([sys.executable, PASMITH] + gen_args_for(args, seed)
                      + ["-o", src], 60)
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


GEN_FLAGS = ["vars", "funcs", "stmts", "depth", "classes", "objs", "strs",
             "recs", "arrs", "enums", "shorts", "excepts", "modeprocs", "intfs"]


def gen_args_for(a, seed):
    """The generation arguments for one seed -- ONE list, used to generate the
    program AND printed as the repro line AND stored in the ledger.

    Never restate them. A hand-written repro line once omitted --classes/--strs, so
    pasting it produced a DIFFERENT program that did not diverge: every finding read
    as "cannot reproduce" and got discarded. A repro line that does not reproduce is
    worse than no repro line at all (bug-t-pasmith-order-dependent-programs).
    """
    args = ["--seed", str(seed)]
    for f in GEN_FLAGS:
        args += ["--%s" % f, str(getattr(a, f))]
    return args


# --intfs is deliberately NOT here: the interface rung diverges on ~100% of seeds
# against a known, filed pxx bug (bug-a-interface-release-on-last-ref-not-destroyed),
# so folding it into --wide would make every --wide slice stop on that one divergence
# (--stop-on-new) and mask every other rung's bugs. Keep it an explicit opt-in rung
# (--intfs N) until that bug is fixed; then add it back here.
WIDE_DEFAULTS = {"recs": 2, "arrs": 2, "enums": 2, "shorts": 2, "excepts": 3,
                 "modeprocs": 2, "strs": 3, "classes": 3}


def add_gen_flags(ap):
    for f, d in (("vars", 8), ("funcs", 3), ("stmts", 12), ("depth", 3),
                 ("objs", 3)):
        ap.add_argument("--%s" % f, type=int, default=d)
    # Opt-in rung, default OFF and deliberately excluded from --wide (see
    # WIDE_DEFAULTS): diverges on ~100% of seeds against a known filed pxx bug.
    ap.add_argument("--intfs", type=int, default=0,
                    help="COM-refcounted interfaces (opt-in; NOT enabled by --wide "
                         "-- see bug-a-interface-release-on-last-ref-not-destroyed)")
    for f in WIDE_DEFAULTS:
        # default None, NOT 0: --wide has to tell "not given" apart from "given as
        # 0", or `--wide --shorts 0` silently turns shortstrings back on. Switching
        # a single rung off is exactly what you need when one is blocked. (The
        # historic example -- --cross needed --shorts 0 while the cross backends
        # rejected records holding a string[N] -- is FIXED: string[N] fields and
        # truncating stores work on all six targets since fec98091/7716bd2a.)
        ap.add_argument("--%s" % f, type=int, default=None)
    ap.add_argument("--wide", action="store_true",
                    help="turn on every widened rung (records + forward pointers, "
                         "enums/sets, arrays, string[N], exceptions, var/const/out "
                         "params) at a sensible size -- see feature-pasmith-widen-grammar")


def apply_wide(a):
    for f, v in WIDE_DEFAULTS.items():
        if getattr(a, f) is None:
            setattr(a, f, v if getattr(a, "wide", False) else 0)
    return a


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
    ap.add_argument("--ledger", metavar="PATH",
                    help="findings ledger (JSON). Known signatures are counted, not "
                         "re-filed -- this is what stops one bug producing 639 reports. "
                         "The updated ledger is written to $FINDINGS/LEDGER.json; add "
                         "--ledger-inplace to also write it back to PATH.")
    ap.add_argument("--ledger-inplace", action="store_true",
                    help="write the updated ledger back to --ledger PATH (interactive "
                         "use). twatch does NOT: it runs with a detached HEAD, where "
                         "writing into the tree blocks the checkout back.")
    ap.add_argument("--ledger-status", action="store_true",
                    help="print the ledger and exit")
    ap.add_argument("--recheck", action="store_true",
                    help="re-run every OPEN finding's example seeds against the current "
                         "compiler; mark the ones that no longer reproduce as fixed. This "
                         "is what un-throttles fuzzing after a fix lands.")
    ap.add_argument("--stop-on-new", action="store_true",
                    help="stop the run as soon as a NEW signature is found. File it, let "
                         "the owning lane fix it; do not spend the rest of the slice "
                         "collecting more instances of the same bug.")
    ap.add_argument("--ticket", metavar="SIG=slug",
                    help="record that a signature has been filed into the owning lane "
                         "(status open -> ticketed). Still throttles fuzzing -- it is "
                         "not fixed yet -- but says triage is done and who has it.")
    ap.add_argument("--sha", default="", help="commit under test (stamped into findings)")
    add_gen_flags(ap)
    a = apply_wide(ap.parse_args())

    if not os.path.exists(PXX):
        print("no stable compiler at %s" % PXX, file=sys.stderr)
        return 2
    if not shutil.which("fpc"):
        print("fpc not found -- the external oracle is the point of this tool", file=sys.stderr)
        return 2

    os.makedirs(FINDINGS, exist_ok=True)
    if a.check is not None:
        return check(a.check, a)

    led = load_ledger(a.ledger) if a.ledger else None
    if a.ticket:
        if led is None:
            print("--ticket needs --ledger PATH", file=sys.stderr)
            return 2
        sig, slug = a.ticket.split("=", 1)
        e = led["findings"].get(sig)
        if e is None:
            print("no such signature: %s" % sig, file=sys.stderr)
            return 2
        e["ticket"] = slug
        e["status"] = "ticketed" if e.get("status") == "open" else e["status"]
        save_ledger(led, a.ledger)
        print("%s -> ticketed as %s" % (sig, slug))
        return 0
    if a.ledger_status:
        if led is None:
            print("--ledger-status needs --ledger PATH", file=sys.stderr)
            return 2
        return ledger_status(led)

    oracles = build_oracles(a.cross)
    workdir = tempfile.mkdtemp(prefix="pasmith.")

    if a.recheck:
        if led is None:
            print("--recheck needs --ledger PATH", file=sys.stderr)
            return 2
        n = len(ledger_open(led))
        print("pasmith_run: rechecking %d open finding(s) against %s" % (n, PXX))
        fixed, still = recheck(led, oracles, workdir, a.sha)
        save_ledger(led, os.path.join(FINDINGS, "LEDGER.json"))
        if a.ledger_inplace:
            save_ledger(led, a.ledger)
        print("pasmith_run: %d fixed, %d still open" % (fixed, still))
        return 0

    if a.seed is not None:
        seeds = [a.seed]
    elif a.seeds:
        seeds = parse_seeds(a.seeds)
    else:
        seeds = None   # timed loop

    print("pasmith_run: compiler=%s\n             oracles=[%s] findings->%s" % (
        PXX, ", ".join(o.name for o in oracles), FINDINGS))

    deadline = time.time() + a.minutes * 60
    n = found = fpc_reject = dups = 0
    new_sigs = []
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
            gen_args = gen_args_for(a, seed)
            rc, out = run([sys.executable, PASMITH] + gen_args + ["-o", src], 60)
            if rc != 0:
                print("GENERATOR FAILED seed=%d: %s" % (seed, out))
                seed += 1
                continue

            res = {o.name: evaluate(o, src, workdir) for o in oracles}
            bad, groups, note, cls = classify(res)
            if not bad:
                seed += 1
                continue

            found += 1
            if "REJECTED" in note and cls == "fpc-reject":
                fpc_reject += 1
            loc = kind = None
            if cls in ("fpc-reject", "pxx-reject"):
                # A rejection localises itself: the diagnostic IS the signature.
                # Tracing it would be pointless -- the program never ran.
                who = "fpc-O0" if cls == "fpc-reject" else "pxx-O0"
                kind = LAST_ERR.get(who) or "compile-fail"
            elif not a.no_localize:
                loc, kind = localize(src, workdir, oracles, groups)
            sig = signature(cls, kind)

            # Dedupe BEFORE printing: a known-open signature is a hit counter, not
            # a report. It is the whole point -- 639 files, one bug.
            fresh = True
            if led is not None:
                fresh = ledger_record(led, sig, cls, kind, seed, gen_args, note, a.sha)
                dups += 0 if fresh else 1
                save_ledger(led, os.path.join(FINDINGS, "LEDGER.json"))
                if a.ledger_inplace:
                    save_ledger(led, a.ledger)
                if not fresh:
                    print("  seed=%-6d %s (known, hit %d)"
                          % (seed, sig, led["findings"][sig]["hits"]))
                    seed += 1
                    continue

            new_sigs.append(sig)
            print("\n=== DIVERGENCE  seed=%d  sig=%s" % (seed, sig))
            print("    %s" % note)
            for val, names in sorted(groups.items(), key=lambda kv: -len(kv[1])):
                print("    %-40s : %s" % (",".join(sorted(names)), val))
            if loc:
                print("    %s" % loc.replace("\n", "\n    "))

            # One report file per SIGNATURE, not per seed. The seed is inside it
            # (and it IS the reproducer), so a second instance of the same bug adds
            # nothing a hit counter doesn't already say.
            stem = os.path.join(FINDINGS, sig)
            shutil.copy(src, stem + ".pas")
            with open(stem + ".txt", "w") as f:
                # WHICH binary produced this. Without it a finding cannot be
                # attributed: "diverges" is meaningless if you don't know what
                # diverged.
                f.write("sig=%s\nseed=%d\nsha=%s\ncompiler=%s\nnote=%s\n\n"
                        % (sig, seed, a.sha or "?", PXX, note))
                for k, v in sorted(res.items()):
                    f.write("%-12s %s\n" % (k, v))
                if loc:
                    f.write("\n%s\n" % loc)
                f.write("\nrepro: tools/pasmith.py %s\n" % " ".join(gen_args))
            seed += 1
            if a.stop_on_new:
                # A new bug is found. Stop. Continuing would spend the slice
                # re-finding it under a hundred other seeds, and that pile is what
                # buried the last one.
                print("\npasmith_run: NEW signature %s -- stopping the slice "
                      "(--stop-on-new)" % sig)
                break
    except KeyboardInterrupt:
        print("\ninterrupted")

    print("\npasmith_run: %d programs, %d divergences (%d = FPC-rejected/generator "
          "bugs, %d = known signatures, %d = NEW)"
          % (n, found, fpc_reject, dups, len(new_sigs)))
    if new_sigs:
        print("pasmith_run: new signature(s): %s" % ", ".join(new_sigs))
    # A clean run is a VALID, useful result (same inverted-success-criteria as
    # feature-ir-fuzzer), not a failure -- so exit 0 either way; the caller
    # reads the count.
    return 0


if __name__ == "__main__":
    sys.exit(main())
