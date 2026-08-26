#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for the three-way verdict in tools/fpc_diff_probe.sh.

feature-t-fpc-probe-needs-a-trunk-oracle.

The stable oracle on this box is FPC 3.2.2 (2021), so "pxx differs from FPC"
twice meant "3.2.2 was wrong and upstream had already fixed it" — once costing a
Track U decide ticket and a DELIBERATE DIVERGENCE comment on a test that was not
one. The probe can now consult a trunk oracle and classify.

Every branch is driven with FAKE compilers, because on a healthy tree only one
of them ever runs: the interesting states (stable wrong, three-way, trunk cannot
build the case) require an FPC bug to occur naturally, which is the whole reason
this classification is hard to get right and easy to leave broken.

The fakes ignore their input and print a fixed string, so one run exercises one
verdict across every probe in the file — which is what makes driving five
verdicts cheap.

Run: python3 tools/fpc_trunk_verdict_devtest.py
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROBE = ROOT / "tools" / "fpc_diff_probe.sh"


def write_fake(path, text, style, tally=None):
    """A compiler that emits a program printing `text`.

    style 'fpc': output path arrives as -o<path>, source last.
    style 'pxx': argv is <source> <outpath>.
    text None: refuse to compile (exit 1) — the 'cast no vote' case.
    tally: a file to append one line to per invocation, for counting oracle use.
    """
    if style == "fpc":
        pick = 'out=""; for a in "$@"; do case "$a" in -o*) out="${a#-o}" ;; esac; done'
    else:
        pick = 'out="$2"'
    count = f'echo x >> "{tally}"\n' if tally else ""
    fail = "exit 1\n" if text is None else ""
    body = "" if text is None else (
        'printf "#!/bin/sh\\necho %s\\n" "$TEXT" > "$out"\nchmod +x "$out"\n')
    path.write_text(
        "#!/bin/sh\n" + count + fail
        + (f'TEXT="{text}"\n' if text is not None else "")
        + pick + "\n" + body)
    path.chmod(0o755)


def run_probe(tmp, stable, trunk, pxx, with_trunk=True):
    """Run the real probe script against the fakes. Returns (rc, stdout)."""
    d = pathlib.Path(tmp)
    tally = d / "trunk_calls"
    write_fake(d / "fake_stable", stable, "fpc")
    write_fake(d / "fake_trunk", trunk, "fpc", tally=tally)
    write_fake(d / "fake_pxx", pxx, "pxx")
    env = dict(os.environ)
    env["FPC"] = str(d / "fake_stable")
    env["PXX_STABLE"] = str(d / "fake_pxx")
    if with_trunk:
        env["FPC_TRUNK"] = str(d / "fake_trunk")
    else:
        env.pop("FPC_TRUNK", None)
    p = subprocess.run(["bash", str(PROBE)], env=env, capture_output=True,
                       text=True, timeout=300)
    calls = len(tally.read_text().splitlines()) if tally.exists() else 0
    return p.returncode, p.stdout + p.stderr, calls


def count(out, pat):
    return len(re.findall(pat, out, re.M))


def case_agreement_is_silent():
    """The healthy state: nothing to classify, nothing to say."""
    with tempfile.TemporaryDirectory() as t:
        rc, out, calls = run_probe(t, "SAME", "SAME", "SAME")
    assert rc == 0, f"agreement failed the run (rc={rc})"
    assert count(out, r"^DIFF  ") == 0, "a DIFF on total agreement"
    assert count(out, r"^FPC-STABLE-BUG") == 0
    assert calls == 0, f"trunk was consulted {calls}x with nothing to classify"
    return "no rows, and the trunk oracle was never invoked"


def case_both_fpcs_agree_and_we_differ():
    """Row 2: a real divergence, ours to explain. Trunk agreeing does not
    make it ours by proof — it makes it ours to ACCOUNT FOR, which is the
    strongest thing outputs can say."""
    with tempfile.TemporaryDirectory() as t:
        rc, out, calls = run_probe(t, "FPCVAL", "FPCVAL", "PXXVAL")
    assert rc == 1, "a real divergence did not fail the run"
    assert count(out, r"^DIFF .*trunk agrees with stable") > 0, out[-400:]
    assert count(out, r"^FPC-STABLE-BUG") == 0, "misfiled as an FPC bug"
    assert calls > 0, "trunk was never consulted on a divergence"
    return "DIFF, annotated 'trunk agrees with stable', run RED"


def case_stable_is_wrong_and_upstream_fixed_it():
    """Row 3 — the worked case, and the entire reason for the ticket.
    decide-forin-mixed-int-float-ctor-vs-fpc reached Track U as a design fork
    because this row could not be expressed. It must NOT fail the run."""
    with tempfile.TemporaryDirectory() as t:
        rc, out, calls = run_probe(t, "OLDBUG", "GOODVAL", "GOODVAL")
    assert count(out, r"^FPC-STABLE-BUG") > 0, "the worked case is not classified"
    assert count(out, r"^DIFF  ") == 0, "an FPC stable bug still counted as ours"
    assert rc == 0, f"an already-fixed FPC bug failed the run (rc={rc})"
    assert "not our divergence" in out, "the row does not say what it means"
    assert "new divergences: 0" in out, "it leaked into the divergence count"
    return "FPC-STABLE-BUG, excluded from the count, run GREEN"


def case_three_way_disagreement_is_its_own_row():
    """The reference moved AND we match neither side. Collapsing this into
    'DIFF' would hide that FPC changed its own behaviour."""
    with tempfile.TemporaryDirectory() as t:
        rc, out, calls = run_probe(t, "STABLEV", "TRUNKV", "PXXV")
    assert count(out, r"^3-WAY") > 0, "three-way disagreement was collapsed"
    assert "every implementation disagrees" in out
    assert rc == 1, "a three-way disagreement did not fail the run"
    return "3-WAY, named apart from DIFF, run RED"


def case_trunk_that_cannot_build_casts_no_vote():
    """An oracle that could not look and an oracle that found nothing must
    never print the same. The case stays a divergence."""
    with tempfile.TemporaryDirectory() as t:
        rc, out, calls = run_probe(t, "FPCVAL", None, "PXXVAL")
    assert "trunk cast no vote" in out, "a silent trunk failure"
    assert count(out, r"^FPC-STABLE-BUG") == 0, "silence read as agreement"
    assert rc == 1, "an unclassified divergence passed"
    return "says so, and stays a divergence"


def case_no_trunk_configured_says_so():
    """Unset must never be silent: that silence is what let two findings be
    measured against 2021 FPC and read as ours."""
    with tempfile.TemporaryDirectory() as t:
        rc, out, calls = run_probe(t, "FPCVAL", "IGNORED", "PXXVAL",
                                   with_trunk=False)
    assert "STABLE ONLY" in out, "a two-way run did not announce its reach"
    assert "already fixed upstream" in out, "it does not say what it cannot tell"
    assert calls == 0, "trunk ran despite being unconfigured"
    assert rc == 1
    return "announces STABLE ONLY and what that cannot distinguish"


def case_bad_trunk_path_is_refused_not_ignored():
    """A typo'd FPC_TRUNK that silently degraded to a two-way run would be the
    worst outcome: the operator believes rows are classified and they are not."""
    with tempfile.TemporaryDirectory() as t:
        d = pathlib.Path(t)
        write_fake(d / "fake_stable", "X", "fpc")
        write_fake(d / "fake_pxx", "X", "pxx")
        env = dict(os.environ)
        env["FPC"] = str(d / "fake_stable")
        env["PXX_STABLE"] = str(d / "fake_pxx")
        env["FPC_TRUNK"] = str(d / "does_not_exist")
        p = subprocess.run(["bash", str(PROBE)], env=env, capture_output=True,
                           text=True, timeout=60)
    assert p.returncode == 2, f"a bad FPC_TRUNK did not refuse (rc={p.returncode})"
    assert "not executable" in p.stdout + p.stderr
    return "exit 2, not a silent downgrade to two-way"


def case_trunk_runs_only_on_divergences():
    """The cost constraint (user, 2026-08-16): the third oracle runs on the
    handful of rows that need it, never across the corpus."""
    with tempfile.TemporaryDirectory() as t:
        rc, out, calls = run_probe(t, "FPCVAL", "FPCVAL", "PXXVAL")
        rows = count(out, r"^DIFF |^FPC-STABLE-BUG|^3-WAY")
        tagged = count(out, r"^DIFF \[known\]|^DIFF \[by design\]")
    assert calls == rows - tagged, \
        f"trunk ran {calls}x for {rows - tagged} untagged rows"
    assert tagged >= 0
    return f"{calls} trunk runs for {rows - tagged} untagged rows, 0 for tagged"


def case_oracle_command_may_carry_flags():
    """A freshly built trunk compiler needs -Fu<its own RTL>, so the override
    has to accept a command line, not just a binary path. A path-only design
    would fail with 'PPU Invalid Version' and look like a compiler bug."""
    src = PROBE.read_text()
    assert 'run_fpc "$FPC"' in src, "the stable oracle is not routed through run_fpc"
    assert 'run_fpc "$FPC_TRUNK"' in src, "the trunk oracle is not routed through run_fpc"
    assert re.search(r"^\s*if \$1 -Mobjfpc", src, re.M), \
        "run_fpc quotes $1, so an oracle carrying flags cannot work"
    assert "command -v fpc " not in src, "a bare `fpc` lookup survives the override"
    return "both oracles accept a command line, unquoted on purpose"


def case_two_copies_do_not_corrupt_each_other():
    """The probe used fixed /tmp/fdp* paths, so a second copy overwrote the
    first's source and binaries — and reported the damage as findings rather
    than failing. Measured 2026-08-26: an overlapping run printed
    `new divergences: 34`, `no-oracle skips: 90`, and rows reading `fpc=[]`,
    which is an overwritten oracle presenting as a disagreeing one.

    This is the case that made the rest of this file possible: a differential
    tool that cannot survive a second copy of itself cannot be devtested either.
    """
    import threading
    out = {}

    def go(key, stable, trunk, pxx):
        with tempfile.TemporaryDirectory() as t:
            out[key] = run_probe(t, stable, trunk, pxx)

    # A: total agreement, must stay silent. B: every row diverges.
    ta = threading.Thread(target=go, args=("A", "SAME", "SAME", "SAME"))
    tb = threading.Thread(target=go, args=("B", "FPCVAL", "FPCVAL", "PXXVAL"))
    ta.start(); tb.start(); ta.join(); tb.join()

    rc_a, out_a, calls_a = out["A"]
    rc_b, out_b, calls_b = out["B"]
    assert rc_a == 0, f"the quiet run was polluted by the noisy one (rc={rc_a})"
    assert count(out_a, r"^DIFF  ") == 0, "a concurrent run injected divergences"
    assert "new divergences: 0" in out_a, out_a[-300:]
    assert calls_a == 0, "the quiet run consulted trunk"
    assert rc_b == 1, "the noisy run lost its divergences to the quiet one"
    assert "fpc=[]" not in out_b, "an overwritten oracle reported as disagreeing"
    return "concurrent runs stay independent; neither sees the other's files"


def case_harness_uses_per_run_scratch():
    """Structural companion to the case above: the fixed paths must be gone
    from the HARNESS. (The Pascal file-I/O probes still name fixed paths inside
    their quoted heredocs — a documented residual, not this assertion's
    subject.)"""
    src = PROBE.read_text()
    assert 'mktemp -d' in src, "no per-run scratch directory"
    assert "trap 'rm -rf" in src, "the scratch directory is never cleaned up"
    harness = src[:src.index("# ---- arithmetic ----")]
    for bad in ("/tmp/fdp.pas", "-o/tmp/fdp_f", "/tmp/fdp_p", "/tmp/fdp_c.log"):
        assert bad not in harness, f"the harness still hardcodes {bad}"
    return "mktemp -d + trap cleanup; no fixed paths left in the harness"


CASES = [
    case_agreement_is_silent,
    case_both_fpcs_agree_and_we_differ,
    case_stable_is_wrong_and_upstream_fixed_it,
    case_three_way_disagreement_is_its_own_row,
    case_trunk_that_cannot_build_casts_no_vote,
    case_no_trunk_configured_says_so,
    case_bad_trunk_path_is_refused_not_ignored,
    case_trunk_runs_only_on_divergences,
    case_oracle_command_may_carry_flags,
    case_two_copies_do_not_corrupt_each_other,
    case_harness_uses_per_run_scratch,
]


def main():
    if not PROBE.exists():
        print(f"  SKIP: {PROBE} missing")
        return 0
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = case()
        except Exception as e:
            print(f"  FAIL {name}: {type(e).__name__}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("fpc trunk verdict OK" if rc == 0 else "fpc trunk verdict BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
