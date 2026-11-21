#!/usr/bin/env python3
"""Every `test-*` Makefile target is in a testmgr tier, or says why not.

A job that fails is loud and a job that skips says so, but a target in NO
tier produces no row at all: twatch, the bisector, the coverage counts and a
person asking "what do we test against" are all silent about it, exactly as
if it did not exist. test-nilpy (238 of 309 .npy files) and test-uforth were
found that way, each by a person deciding to ask, and then six real-program
targets (bug-t-six-real-program-jobs-are-in-no-tier-so-they-never-run). This
asks instead of a person:

    Makefile `^test-[a-z0-9-]+:`  minus  every tier's targets  minus  OPT_OUT

must be empty. A new test target therefore lands in a tier or in OPT_OUT with
its reason; the decision is recorded instead of being an absence.

OPT_OUT has three kinds, and the kind is checked, not trusted:
  alias    -- runs only other test-* targets; every one of them must be tiered
              (checked from the Makefile), or the alias is a hole in disguise.
  outside  -- deliberately not a tier job; the reason says what it needs.
  hole     -- NOT a decision: unplaced, waiting for a tier chosen on measured
              cost. Printed on every run, so the list cannot quietly become
              the place targets go to be forgotten.

Also fails on an OPT_OUT entry that is no longer a Makefile target, or that a
tier now names: a stale list certifies nothing.

usage: tools/check_tier_coverage.py [--self-check]
  --self-check  the positive control: a fixture Makefile with one unlisted
                target MUST fail, a stale entry MUST fail, and a broken alias
                MUST fail -- a guard over an empty remainder passes forever.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SIX = "bug-t-six-real-program-jobs-are-in-no-tier-so-they-never-run"

OPT_OUT = {
    # aliases: one name for a set of tiered targets
    "test-c": ("alias", "test-core + test-c-conformance, both tiered"),
    "test-c-conformance-cross": ("alias", "the four per-arch C conformance targets"),
    "test-sqlite-threads": ("alias", "the four per-arch sqlite-threads targets"),
    # outside: needs something a tier box is not promised to have
    "test-fpc": ("outside", "needs FPC; the release workflow runs it (Makefile comment)"),
    "test-fpc-seed-checked": ("outside", "needs FPC and an FPC build of compiler.pas"),
    "test-asm-emit": ("outside", "part of test-fpc: built with FPC, llvm-mc oracle values"),
    "test-freebsd": ("outside", "needs the FreeBSD VM image ($PXX_VM_DIR)"),
    "test-freebsd-arm64": ("outside", "port family: FreeBSD/arm64 image"),
    "test-netbsd": ("outside", "needs the NetBSD VM image"),
    "test-netbsd-arm64": ("outside", "port family: NetBSD/arm64 image"),
    "test-openbsd": ("outside", "needs the OpenBSD VM image"),
    "test-openbsd-arm64": ("outside", "needs the OpenBSD/arm64 image (~400 s under TCG)"),
    "test-openbsd-libc": ("outside", "needs the OpenBSD VM image (--rtl-libc build)"),
    "test-openbsd-arm64-libc": ("outside", "needs the OpenBSD/arm64 image (--rtl-libc build)"),
    "test-dragonfly": ("outside", "needs the DragonFly VM image"),
    "test-minix": ("outside", "needs the MINIX VM image"),
    "test-windows": ("outside", "needs a Windows host or VM"),
    "test-frozen": ("outside", "a rerun of the suites with FROZEN_PXXFLAGS, not its own jobs"),
    "test-managed": ("outside", "a rerun of the suites with COMPILER_MANAGED, not its own jobs"),
    "test-nilpy-frozen": ("outside", "test-nilpy rerun with FROZEN_PXXFLAGS"),
    "test-nilpy-managed": ("outside", "test-nilpy rerun with COMPILER_MANAGED"),
    "test-no-nilpy-build": ("outside", "opt-in by its own comment: breaks until a new Py* call gets its stub"),
    "test-c-conformance-esp32c3": ("outside", "needs an ESP-IDF checkout, ~30 s a test (run by hand or sharded)"),
    "test-c-conformance-esp32s3": ("outside", "needs an ESP-IDF checkout, ~30 s a test (run by hand or sharded)"),
    "test-dropbear": ("outside", "opt-in: needs openssh-client/server, ~5 min (Makefile comment)"),
    # holes: no decision yet -- these are the ticket, not an answer to it
    "test-chess-perft": ("hole", SIX),
    "test-duktape": ("hole", SIX),
    "test-sqlite-parity": ("hole", SIX),
    "test-wasm32": ("hole", SIX + " (51 jobs, 49 of them qemu)"),
    "test-c-abi-cross": ("hole", "no placement recorded (found by this guard, 2026-11-21)"),
    "test-c-abi-glibc-oracle": ("hole", "no placement recorded (found by this guard, 2026-11-21)"),
    "test-c-float-const-cross": ("hole", "no placement recorded (found by this guard, 2026-11-21)"),
    "test-packenum-gcc-oracle": ("hole", "no placement recorded (found by this guard, 2026-11-21)"),
    "test-packrecords-c-gcc-oracle": ("hole", "no placement recorded (found by this guard, 2026-11-21)"),
}

TARGET_RE = re.compile(r"^(test-[a-z0-9-]+):([^=\n]*)$", re.M)


def makefile_targets(text):
    """{target: [its test-* prerequisites]} for every `test-*:` rule line."""
    out = {}
    for m in TARGET_RE.finditer(text):
        deps = [d for d in m.group(2).split() if d.startswith("test-")]
        out.setdefault(m.group(1), [])
        out[m.group(1)] += deps
    return out


def check(text, tiered, opt_out):
    """The findings, as (kind, message); kind 'fail' or 'hole'."""
    found = []
    targets = makefile_targets(text)
    for t in sorted(targets):
        if t in tiered:
            continue
        if t not in opt_out:
            found.append(("fail", "%s is in no tier and not in OPT_OUT: add it to a "
                          "tier in tools/testmgr.py, or to OPT_OUT in %s with its reason"
                          % (t, os.path.basename(__file__))))
            continue
        kind, why = opt_out[t]
        if kind == "alias":
            bad = [d for d in targets[t] if d not in tiered]
            if not targets[t]:
                found.append(("fail", "%s is listed as an alias but has no test-* "
                              "prerequisites" % t))
            elif bad:
                found.append(("fail", "%s is listed as an alias, but %s %s in no tier"
                              % (t, ", ".join(bad), "is" if len(bad) == 1 else "are")))
        elif kind == "hole":
            found.append(("hole", "%s -- %s" % (t, why)))
        elif kind != "outside":
            found.append(("fail", "%s: unknown OPT_OUT kind %r" % (t, kind)))
    for t in sorted(opt_out):
        if t not in targets:
            found.append(("fail", "OPT_OUT names %s, which is no longer a Makefile "
                          "target: drop it" % t))
        elif t in tiered:
            found.append(("fail", "OPT_OUT names %s, which a tier now runs: drop it "
                          "from OPT_OUT" % t))
    return found


def tiered_targets():
    sys.path.insert(0, HERE)
    import testmgr                                      # noqa: E402
    return set(j for v in testmgr.TIERS.values() for j in v)


def self_check():
    """The guard must be able to fail, each way it claims to."""
    fixture = ("test-a: $(COMPILER)\n\techo a\n"
               "test-b: $(COMPILER)\n\techo b\n"
               "test-ab: test-a test-b\n"
               "test-new: $(COMPILER)\n\techo new\n")
    tiered = {"test-a", "test-b"}
    oks = []
    f = check(fixture, tiered, {"test-ab": ("alias", "x")})
    oks.append(("an unlisted target fails",
                any(k == "fail" and "test-new" in m for k, m in f)))
    f = check(fixture, tiered, {"test-ab": ("alias", "x"), "test-new": ("outside", "x"),
                                "test-gone": ("outside", "x")})
    oks.append(("a stale OPT_OUT entry fails",
                any(k == "fail" and "test-gone" in m for k, m in f)))
    f = check(fixture, {"test-a"}, {"test-ab": ("alias", "x"), "test-new": ("outside", "x"),
                                     "test-b": ("outside", "x")})
    oks.append(("an alias over an untiered target fails",
                any(k == "fail" and "test-ab" in m for k, m in f)))
    f = check(fixture, tiered, {"test-ab": ("alias", "x"), "test-new": ("outside", "x"),
                                "test-a": ("outside", "x")})
    oks.append(("an OPT_OUT entry a tier now runs fails",
                any(k == "fail" and "test-a," in m + "," for k, m in f)))
    f = check(fixture, tiered, {"test-ab": ("alias", "x"), "test-new": ("hole", "t")})
    oks.append(("a hole is reported, not failed",
                not any(k == "fail" for k, _ in f) and any(k == "hole" for k, _ in f)))
    f = check(fixture, tiered, {"test-ab": ("alias", "x"), "test-new": ("outside", "x")})
    oks.append(("a fully placed fixture is clean", f == []))
    for name, ok in oks:
        print("  %-4s %s" % ("ok" if ok else "FAIL", name))
    return all(ok for _, ok in oks)


def main():
    if "--self-check" in sys.argv[1:]:
        if not self_check():
            print("check_tier_coverage: self-check FAILED -- the guard cannot fail "
                  "the way it says it does")
            return 1
        print("check_tier_coverage: self-check OK")
    text = open(os.path.join(ROOT, "Makefile")).read()
    found = check(text, tiered_targets(), OPT_OUT)
    fails = [m for k, m in found if k == "fail"]
    holes = [m for k, m in found if k == "hole"]
    for m in fails:
        print("FAIL " + m)
    if holes:
        print("check_tier_coverage: %d target(s) are KNOWN HOLES, in no tier and "
              "awaiting placement:" % len(holes))
        for m in holes:
            print("  hole " + m)
    n = len(makefile_targets(text))
    if fails:
        print("check_tier_coverage: %d problem(s) over %d test targets" % (len(fails), n))
        return 1
    print("check_tier_coverage: OK -- %d test targets, each tiered or opted out "
          "with a reason (%d of them holes)" % (n, len(holes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
