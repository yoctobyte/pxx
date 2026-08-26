#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: `pin_built` must read the WORK, not the wrapper.

A job is `pin_built` when it builds against $(PXX_STABLE) rather than a
HEAD-built compiler. The flag decides two things that matter far from here:
twatch.pin_immune() uses it to know a red cannot be blamed on a compiler
commit, and it is the set that becomes unattributable when a pin moves
underneath a run (bug-t-a-pin-that-moves-mid-run-is-not-detected).

PINNED_INVOKE_RE alone gets that wrong for a job whose recipe SHELLS OUT: the
`demos` job's whole body is `make demos`, so the pinned path lives one level
down in the Makefile and the regex reads the wrapper. It reported pin_built=0
on a job that builds every example against the pin. Harmless only while demos
stays advisory — the day a shell-out job gates anything, it silently is not.

Hence the target-name half of the rule. The guards:

  * a shell-out job whose target is known pin-built is pin_built anyway;
  * a recipe naming the pinned path directly still is, target unknown or not;
  * an explicit ./compiler/pascal26 in the body OVERRIDES both — a job that
    invokes the HEAD compiler is not pin-immune whatever its target is called;
  * and the tier-level counts, which are the number the pin-window answer is
    made of: quick/native/limited carry ZERO pin-built jobs, so a pin taken
    while one of those runs cannot corrupt its verdict.

Run: tools/testmgr_pin_built_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm",
                                              os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)

PINNED = "stable_linux_amd64/default/pinned test/x.pas $(TESTTMP)/x"
HEAD = "./compiler/pascal26 test/x.pas $(TESTTMP)/x"


def t_a_shell_out_job_is_still_pin_built():
    j = tm.Job("demos", 0, ["out=$(make demos 2>&1); printf '%s\\n' \"$out\""])
    assert j.pin_built, "demos reads its wrapper, not the pin one level down"
    return "target-name rule reaches a recipe with no pinned path in it"


def t_a_direct_pinned_invocation_needs_no_target():
    j = tm.Job("some-future-target", 0, [PINNED])
    assert j.pin_built, "the regex half must keep working on its own"
    return "recipe naming the pin is pin_built with an unknown target"


def t_the_head_compiler_overrides_the_target_name():
    j = tm.Job("lib-test", 0, [PINNED, HEAD])
    assert not j.pin_built, "a job invoking HEAD's compiler is not pin-immune"
    j2 = tm.Job("demos", 0, ["make demos", HEAD])
    assert not j2.pin_built, "same, via the target-name half"
    return "an explicit ./compiler/pascal26 wins over both halves"


def t_an_ordinary_job_is_not_pin_built():
    j = tm.Job("test-core", 0, [HEAD])
    assert not j.pin_built
    return "the common case stays false"


def t_only_the_full_tier_can_straddle_a_pin():
    """The measurement the pin-window answer rests on. If this ever changes,
    'pin during a native window is safe' silently stops being true."""
    counts = {}
    for tier in ("quick", "native", "limited", "full"):
        jobs = list(tm.generate(tier))
        counts[tier] = sum(1 for j in jobs if j.pin_built)
    for tier in ("quick", "native", "limited"):
        assert counts[tier] == 0, (
            "%s now has %d pin-built job(s) — a pin taken during one of these "
            "runs can no longer be called safe" % (tier, counts[tier]))
    assert counts["full"] > 0, "full lost its pin-built jobs entirely"
    return "quick/native/limited 0, full %d" % counts["full"]


def t_the_full_tiers_pin_built_set_is_the_known_targets():
    jobs = [j for j in tm.generate("full") if j.pin_built]
    targets = sorted({j.target for j in jobs})
    assert targets == sorted(tm.PIN_BUILT_TARGETS), (
        "pin-built targets drifted from PIN_BUILT_TARGETS: %s vs %s"
        % (targets, sorted(tm.PIN_BUILT_TARGETS)))
    return "full's pin-built set is exactly %s" % (targets,)


def main():
    rc = 0
    for fn in (t_a_shell_out_job_is_still_pin_built,
               t_a_direct_pinned_invocation_needs_no_target,
               t_the_head_compiler_overrides_the_target_name,
               t_an_ordinary_job_is_not_pin_built,
               t_only_the_full_tier_can_straddle_a_pin,
               t_the_full_tiers_pin_built_set_is_the_known_targets):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("pin_built OK" if rc == 0 else "pin_built BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
