#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for the oracle wide-state precondition in tools/fpc_diff_probe.sh.

FPC has two knobs that change a non-ASCII answer, on different axes: the source
codepage (how a literal becomes an AnsiString) and the widestring manager (how
an AnsiString widens to a WideString). Measured 2026-08-30, pxx matches the
UN-knobbed oracle on both — so a knobbed $FPC does not give a better answer for
an AnsiString<->WideString crossing, it MANUFACTURES a divergence. The probe
detects the state with a non-ASCII canary and SKIPs `needswide` cases rather
than reporting the knob as ours.

Driven with FAKE compilers, for the same reason the trunk-verdict devtest is:
reaching the knobbed states for real needs a cwstring-enabled FPC build, which
is exactly the configuration nobody has when the check silently stops working.

The fake fpc answers the CANARY differently from every other probe, so one run
exercises one oracle state across the whole corpus while leaving every ordinary
probe in agreement — which is what keeps a state cheap to drive.

Run: python3 tools/fpc_oracle_wide_devtest.py
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROBE = ROOT / "tools" / "fpc_diff_probe.sh"

# The three probes that carry `needswide`. Named here so that deleting one from
# the corpus without deleting it here is a failure rather than a quiet loss of
# the only coverage this axis has.
NEEDSWIDE = ["widestring-nonascii", "widestring-nonascii-narrow",
             "widechar-nonascii-index"]


def write_fakes(d, canary, canary_fails=False, tally=None):
    """A fake fpc that answers the canary with `canary` and everything else
    with `same`, plus a fake pxx that always answers `same`."""
    count = f'echo x >> "{tally}"\n' if tally else ""
    fail = ('if grep -q "program fdpcap" "$src" 2>/dev/null; then exit 1; fi\n'
            if canary_fails else "")
    fpc = d / "fake-fpc"
    fpc.write_text(
        "#!/bin/sh\n" + count +
        'out=""; src=""\n'
        'for a in "$@"; do case "$a" in -o*) out="${a#-o}" ;; *.pas) src="$a" ;; esac; done\n'
        + fail +
        'if grep -q "program fdpcap" "$src" 2>/dev/null; then T="%s"; else T="same"; fi\n'
        'printf "#!/bin/sh\\necho %%s\\n" "$T" > "$out"\nchmod +x "$out"\n' % canary)
    fpc.chmod(0o755)
    pxx = d / "fake-pxx"
    pxx.write_text('#!/bin/sh\nprintf "#!/bin/sh\\necho same\\n" > "$2"\n'
                   'chmod +x "$2"\n')
    pxx.chmod(0o755)
    return fpc, pxx


def run(canary, canary_fails=False, tally_path=None):
    with tempfile.TemporaryDirectory() as tmp:
        d = pathlib.Path(tmp)
        tally = str(d / "tally") if tally_path is not None else None
        fpc, pxx = write_fakes(d, canary, canary_fails, tally)
        p = subprocess.run(
            ["bash", str(PROBE)], cwd=tmp, text=True, capture_output=True,
            env={"PATH": "/usr/bin:/bin", "HOME": tmp,
                 "FPC": str(fpc), "PXX_STABLE": str(pxx)})
        n = 0
        if tally:
            try:
                n = len(pathlib.Path(tally).read_text().split())
            except FileNotFoundError:
                n = 0
        return p.returncode, p.stdout + p.stderr, n


def case_plain_oracle_compares_the_crossings():
    rc, out, _ = run("5 5")
    for name in NEEDSWIDE:
        assert f"SKIP        {name}" not in out, f"{name} skipped under a plain oracle"
    assert "oracle wide-state: plain" in out, out[-800:]
    return "canary [5 5] -> the non-ASCII crossings are compared, not skipped"


def case_knobbed_oracle_skips_them_and_says_why():
    rc, out, _ = run("5 4")            # a widestring manager is installed
    for name in NEEDSWIDE:
        assert f"SKIP        {name}" in out, f"{name} was compared against a knobbed oracle"
    assert "oracle wide-state: knobbed" in out, out[-800:]
    assert "were SKIPPED, not compared" in out
    # The distinction the whole check exists for.
    assert "changes the ORACLE's" in out
    return "canary [5 4] -> 3 SKIPs and a summary that blames the oracle, not pxx"


def case_codepage_knob_is_caught_too():
    rc, out, _ = run("4 4")            # {$codepage utf8}: the OTHER axis
    assert "oracle wide-state: knobbed" in out, out[-800:]
    for name in NEEDSWIDE:
        assert f"SKIP        {name}" in out
    return "canary [4 4] -> the source-codepage axis is caught, not just cwstring"


def case_uncharacterisable_oracle_is_not_treated_as_plain():
    # An oracle we cannot describe and an oracle we know is wrong must not
    # print the same, and neither may read as a pass.
    rc, out, _ = run("", canary_fails=True)
    assert "oracle wide-state: unknown" in out, out[-800:]
    for name in NEEDSWIDE:
        assert f"SKIP        {name}" in out
    assert "oracle wide-state: plain" not in out
    return "canary cannot compile -> unknown, and the crossings still skip"


def case_silence_when_nothing_asked():
    # A run that never consulted the canary must not assert a state. Driven by
    # a source-shape check because reaching it needs a corpus with no needswide
    # probe -- which is the state this file exists to prevent.
    src = PROBE.read_text(encoding="utf-8")
    assert 'if [ -n "$ORACLE_WIDE" ]; then' in src, \
        "the summary reports the wide-state unconditionally"
    assert 'ORACLE_WIDE=""' in src, "the state is not lazily initialised"
    return "the summary is guarded on the canary having actually been consulted"


def case_the_canary_is_non_ascii():
    # An ASCII canary answers '5 5' under every knob: a UTF-8 byte count and a
    # UTF-16 unit count are the same number on ASCII. This is the check that
    # survives someone 'cleaning up' the escape into a plain letter.
    src = PROBE.read_text(encoding="utf-8")
    i = src.index("oracle_wide_state()")
    body = src[i:i + 900]
    assert "\\303\\251" in body, \
        "the canary literal is ASCII, so it cannot distinguish any knob"
    return "the canary literal is a raw UTF-8 U+00E9, not an ASCII stand-in"


def case_a_skipped_crossing_costs_no_compile():
    # The check runs before anything is built. Claimed in a comment, so it is
    # worth an assertion: knobbed must cost the canary and nothing more.
    _, _, n_plain = run("5 5", tally_path=True)
    _, _, n_knob = run("5 4", tally_path=True)
    assert n_knob < n_plain, f"knobbed cost {n_knob} fpc runs, plain cost {n_plain}"
    assert n_plain - n_knob == len(NEEDSWIDE), \
        f"expected {len(NEEDSWIDE)} saved compiles, saved {n_plain - n_knob}"
    return f"a knobbed oracle skips before compiling: {n_plain} -> {n_knob} fpc runs"


CASES = [
    case_plain_oracle_compares_the_crossings,
    case_knobbed_oracle_skips_them_and_says_why,
    case_codepage_knob_is_caught_too,
    case_uncharacterisable_oracle_is_not_treated_as_plain,
    case_silence_when_nothing_asked,
    case_the_canary_is_non_ascii,
    case_a_skipped_crossing_costs_no_compile,
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
    print("fpc oracle wide-state OK" if rc == 0 else "fpc oracle wide-state BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
