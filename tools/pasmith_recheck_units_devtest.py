#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Guards for pasmith_run.recheck() — the THREE outcomes, and multi-unit regen.

WHAT WENT WRONG (2026-08-30). recheck() rebuilt each example seed by hand:

    run([sys.executable, PASMITH] + ex["args"] + ["-o", src], 60)

but pasmith REJECTS `--units N -o FILE` ("--units needs --outdir (a unit set is
several files)"). So for every multi-unit finding the regeneration failed on
every tick, forever. The failure arm then did this:

    if rc != 0:
        reproduces = True      # cannot judge: keep it open, loudly

and it was not loud: it printed the SAME "still reproduces" line as a genuine
reproduction. A failure to MEASURE was reported as a MEASUREMENT, in the
direction that manufactures work. `pxx-self_unitrec` was fixed by 10c869750 and
was still being reported as reproducing, which nearly bought a second -O3 bug
ticket for a bug that did not exist.

Both halves are guarded here, because either one alone still leaves a liar:
fixing only the regeneration leaves the next unmeasurable case silent, and
fixing only the wording leaves --units findings permanently un-closeable.

Pure: no compiler, no fpc. generate/evaluate/classify are stubbed for the
outcome guards; the ONE guard that shells out runs pasmith.py, which is
plain Python, to confirm the premise is still true rather than assumed.

Negative control, run 2026-08-30 against the pre-fix file: 9 of 11 red, and the
two that stayed green (the pasmith premise, generate()'s own --units branch) are
exactly the two describing code the fix did not touch. Read that control with one
caveat: the old recheck() did not call generate() at all, so the two
t_unmeasurable_* guards go red there by a DIFFERENT route than the bug -- the
stub is bypassed and a real single-file generation succeeds. They bind the new
behaviour correctly; they are not a reenactment of the old failure. A control
that goes red for the wrong reason still looks like a passing control, so the
distinction is written down rather than left to be inferred from a count.
"""
import importlib.util
import io
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "pasmith_run.py")


def load():
    sp = importlib.util.spec_from_file_location("pasmith_run_under_test", SRC)
    m = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m


def ledger(examples, sig="s_one"):
    return {"version": 1, "findings": {sig: {"status": "open", "examples": examples}}}


class Capture:
    """Collect print() output from recheck without a real terminal."""
    def __enter__(self):
        self.buf = io.StringIO()
        self.old, sys.stdout = sys.stdout, self.buf
        return self

    def __exit__(self, *a):
        sys.stdout = self.old
        self.text = self.buf.getvalue()
        return False


def run_recheck(m, led, gen, bad):
    """recheck() with generate/evaluate/classify stubbed. Returns (counts, text)."""
    m.emit = gen
    m.evaluate = lambda o, src, wd: "chk"
    m.classify = lambda res: (bad, None, None, "cls")
    with tempfile.TemporaryDirectory() as wd:
        with Capture() as cap:
            counts = m.recheck(led, [], wd, sha="deadbeef")
    return counts, cap.text


# --- the premise -----------------------------------------------------------

def t_pasmith_still_rejects_units_with_dash_o():
    """The bug's PREMISE, re-derived rather than quoted.

    If pasmith ever learns to accept `--units N -o FILE`, this guard goes red
    and says so -- better than a comment asserting a behaviour nobody rechecks,
    which is the failure shape this whole file exists to catch.
    """
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "x.pas")
        r = subprocess.run(
            [sys.executable, os.path.join(ROOT, "tools", "pasmith.py"),
             "--seed", "1", "--units", "2", "-o", out],
            capture_output=True, text=True, timeout=60)
    assert r.returncode != 0, "pasmith now ACCEPTS --units with -o (rc=0)"
    blob = (r.stdout + r.stderr).lower()
    assert "outdir" in blob, "rejected, but not for the --outdir reason: %r" % blob[:200]
    return "pasmith rejects --units+-o (rc=%d)" % r.returncode


# --- regeneration ----------------------------------------------------------

def t_recheck_regenerates_through_emit():
    """recheck must NOT hand-roll the generator command line.

    emit() is the single place that knows a unit set needs --outdir. Two call
    sites building that command line is how the two drifted apart.
    """
    src = io.open(SRC, encoding="utf-8").read()
    body = src[src.index("def recheck("):src.index("def ledger_status(")]
    assert "emit(" in body, "recheck no longer calls emit()"
    assert '"-o"' not in body, "recheck builds its own -o command line again"
    assert "PASMITH]" not in body, "recheck invokes the generator directly again"
    return "recheck regenerates via emit()"


def t_recheck_walks_more_than_the_throttle_set():
    """ledger_open() answers "what throttles"; recheck asks "what to re-measure".

    Reusing one set for both meant a `dodged` finding could be fixed and nothing
    would ever notice — latched, because the arm that would notice never ran.
    """
    m = load()
    led = {"version": 1, "findings": {
        "a": {"status": "open", "examples": []},
        "b": {"status": "ticketed", "examples": []},
        "c": {"status": "dodged", "examples": []},
        "d": {"status": "fixed", "examples": []}}}
    assert set(m.ledger_recheckable(led)) == {"a", "b", "c"}, m.ledger_recheckable(led)
    assert set(m.ledger_open(led)) == {"a", "b"}, "the THROTTLE set must not widen"
    return "recheck walks open+ticketed+dodged; throttle stays open+ticketed"


def t_dodged_is_regenerated_with_dodges_off():
    """A dodge REMOVES the shape, so a dodged entry measured with the dodge
    active is a green verdict from a program that never had the chance to fail.

    This is the trap that makes the population widening dangerous on its own:
    the naive fix manufactures false FIXEDs, the same failure in the opposite
    direction. Both halves have to ship together.
    """
    m = load()
    seen = {}

    def gen(args, wd, seed, env=None, **kw):
        seen[args[1]] = env
        return 0, "", "/x.pas"

    led = {"version": 1, "findings": {
        "dod": {"status": "dodged",
                "examples": [{"seed": 11, "args": ["--seed", "11"]}]},
        "opn": {"status": "open",
                "examples": [{"seed": 22, "args": ["--seed", "22"]}]}}}
    run_recheck(m, led, gen, bad=True)
    assert seen["11"] == {"PASMITH_NO_DODGES": "1"}, seen
    assert seen["22"] is None, "a non-dodged entry must regenerate normally: %r" % (seen,)
    return "a dodged entry regenerates with PASMITH_NO_DODGES=1"


def t_pasmith_honours_the_dodge_override():
    """The generator half. Without it the env var is a no-op and the recheck of
    a dodged entry silently measures the dodged program anyway.
    """
    src = io.open(os.path.join(ROOT, "tools", "pasmith.py"), encoding="utf-8").read()
    assert 'PASMITH_NO_DODGES' in src, "pasmith.py does not read PASMITH_NO_DODGES"
    blk = src[src.index('PASMITH_NO_DODGES'):]
    blk = blk[:blk.index("def ")]
    for name in ("NO_SHORTSTRING_TRUNCATION", "NO_ONE_CHAR_STRING_LITERAL",
                 "NO_BARE_NOT_ORD"):
        assert name in blk, "%s is not forced off by PASMITH_NO_DODGES" % name
    declared = set(re.findall(r"^(NO_[A-Z_]+) *=", src, re.M))
    forced = set(re.findall(r"(NO_[A-Z_]+) *= *False", blk))
    assert declared == forced, (
        "dodges declared but not forced off: %s — a new NO_* constant must be "
        "added to the override, or a dodged recheck silently measures the "
        "dodged program" % (declared - forced))
    return "every NO_* dodge is forced off by the override"


def t_emit_uses_outdir_for_units():
    """The other half of the pair: emit() must special-case --units."""
    src = io.open(SRC, encoding="utf-8").read()
    body = src[src.index("def emit("):src.index("def generate(")]
    assert '"--units" in args' in body, "emit() no longer branches on --units"
    assert '"--outdir"' in body, "emit() no longer passes --outdir for a unit set"
    return "emit() writes a unit set with --outdir"


def t_the_generator_command_line_exists_once():
    """THE structural guard. Four sites knew that a unit set needs --outdir:
    generate(), localize(), recheck() and --check. Two of the four had it wrong.

    Three mechanisms serving one concept is a design flaw, and teaching the
    broken ones the rule would have made it four. So the rule lives in emit()
    and the invocation appears nowhere else. If this goes red, someone added a
    fifth copy -- add a caller, not another copy.
    """
    src = io.open(SRC, encoding="utf-8").read()
    lines = [(i + 1, l) for i, l in enumerate(src.split("\n")) if "PASMITH]" in l]
    body = src[src.index("def emit("):src.index("def generate(")]
    outside = [(n, l.strip()) for n, l in lines if l.strip() not in
               [x.strip() for x in body.split("\n")]]
    assert not outside, "the generator is invoked outside emit(): %r" % outside
    assert len(lines) == 2, "emit() should invoke it twice (-o and --outdir), got %d" % len(lines)
    return "the generator command line exists only in emit()"


def t_check_mode_goes_through_emit():
    """--check was the FOURTH site, and it was broken the same way: it passed
    -o unconditionally, so `--check --units N` could not generate one seed."""
    src = io.open(SRC, encoding="utf-8").read()
    body = src[src.index("fpc = Oracle("):src.index("GEN_FLAGS = ")]
    assert "emit(" in body, "--check no longer regenerates through emit()"
    assert '"-o", src' not in body, "--check builds its own -o command line again"
    return "--check generates through emit()"


def t_check_mode_puts_the_source_dir_on_the_unit_path():
    """The second half of --check's --units breakage: even once the unit SET is
    written, FPC cannot find the units without -Fu. evaluate() applies that
    unconditionally and says why; --check must match, or the two modes diverge
    for a reason that is not a generator bug.
    """
    src = io.open(SRC, encoding="utf-8").read()
    body = src[src.index("fpc = Oracle("):src.index("GEN_FLAGS = ")]
    assert '"-Fu"' in body or '"-Fu" +' in body, "--check does not -Fu the source dir"
    return "--check puts the program's own directory on the unit path"


def t_localize_no_longer_duplicates_the_rule():
    """localize() had a CORRECT copy of the --units rule. Correct-but-duplicated
    is still the design flaw: it is the copy that stays right while another
    drifts, which is exactly what happened here.
    """
    src = io.open(SRC, encoding="utf-8").read()
    body = src[src.index("def localize("):src.index("def sentinel_kind(")]
    assert "emit(" in body, "localize() no longer regenerates through emit()"
    assert "traced_u" not in body, "localize() still builds its own unit-set path"
    assert "trace=True" in body, "localize() must still ask for a TRACED rebuild"
    return "localize() shares the rule instead of copying it"


def t_multi_unit_example_is_judgeable():
    """End-to-end shape: a --units finding whose oracles now agree marks FIXED.

    Before the fix this was unreachable -- regeneration failed first, so the
    entry could never leave `open` no matter what the compiler did.
    """
    m = load()
    calls = []

    def gen(args, wd, seed, **kw):
        calls.append(list(args))
        return 0, "", os.path.join(wd, "p%d.pas" % seed)

    led = ledger([{"seed": 92001, "args": ["--seed", "92001", "--units", "2"]}])
    (fixed, still, unknown), text = run_recheck(m, led, gen, bad=False)
    assert (fixed, still, unknown) == (1, 0, 0), (fixed, still, unknown)
    assert led["findings"]["s_one"]["status"] == "fixed"
    assert calls == [["--seed", "92001", "--units", "2"]], calls
    return "a --units finding can reach fixed"


# --- the three outcomes ----------------------------------------------------

def t_returns_three_counts():
    m = load()
    led = ledger([{"seed": 1, "args": ["--seed", "1"]}])
    counts, _ = run_recheck(m, led, lambda a, w, s, **kw: (0, "", "/x.pas"), bad=True)
    assert len(counts) == 3, "recheck returns %d value(s), want 3" % len(counts)
    return "recheck returns (fixed, still, unknown)"


def t_unmeasurable_is_not_reported_as_reproducing():
    """The core lie. A regeneration failure must not print as a reproduction."""
    m = load()
    led = ledger([{"seed": 7, "args": ["--seed", "7"]}])
    (fixed, still, unknown), text = run_recheck(
        m, led, lambda a, w, s, **kw: (2, "boom: --units needs --outdir", ""), bad=False)
    assert (fixed, still, unknown) == (0, 0, 1), (fixed, still, unknown)
    assert "still reproduces" not in text, "unmeasurable printed as reproducing:\n" + text
    assert "CANNOT JUDGE" in text, "no distinct word for unmeasurable:\n" + text
    return "regen failure prints CANNOT JUDGE, not 'still reproduces'"


def t_unmeasurable_is_not_reported_as_fixed_either():
    """Unknown is unknown in BOTH directions -- the entry stays open."""
    m = load()
    led = ledger([{"seed": 7, "args": ["--seed", "7"]}])
    _, text = run_recheck(m, led, lambda a, w, s, **kw: (2, "boom", ""), bad=False)
    assert led["findings"]["s_one"]["status"] == "open", "unmeasurable was closed"
    assert "FIXED" not in text, text
    return "unmeasurable entry stays open"


def t_unmeasurable_names_the_seed_and_the_reason():
    """A CANNOT JUDGE with no cause is a shrug. It must be actionable."""
    m = load()
    led = ledger([{"seed": 92001, "args": ["--seed", "92001"]}])
    _, text = run_recheck(
        m, led, lambda a, w, s, **kw: (2, "pasmith.py: error: --units needs --outdir", ""),
        bad=False)
    assert "92001" in text, "seed not named:\n" + text
    assert "outdir" in text, "generator's own message not carried:\n" + text
    return "CANNOT JUDGE carries seed + generator message"


def t_no_examples_is_unknown_not_fixed():
    """Zero measurements is not evidence of a fix.

    The old loop simply did not execute, fell through to the else, and printed
    'FIXED (0 example seed(s) now agree)' -- a green verdict from no data.
    """
    m = load()
    led = ledger([])
    (fixed, still, unknown), text = run_recheck(
        m, led, lambda a, w, s, **kw: (0, "", "/x.pas"), bad=False)
    assert (fixed, still, unknown) == (0, 0, 1), (fixed, still, unknown)
    assert led["findings"]["s_one"]["status"] == "open"
    return "an entry with no examples cannot be marked fixed"


def t_genuine_reproduction_still_says_so():
    """The fix must not turn real reproductions into shrugs."""
    m = load()
    led = ledger([{"seed": 1, "args": ["--seed", "1"]}])
    (fixed, still, unknown), text = run_recheck(
        m, led, lambda a, w, s, **kw: (0, "", "/x.pas"), bad=True)
    assert (fixed, still, unknown) == (0, 1, 0), (fixed, still, unknown)
    assert "still reproduces" in text, text
    assert "CANNOT JUDGE" not in text, text
    return "a real reproduction is unchanged"


def t_summary_line_surfaces_unknowns():
    """twatch reads the LAST LINE of stdout and nothing else.

    If the unknown count is not in that line, the daemon's log says '0 fixed,
    0 still open' while an entry silently went unmeasured -- the same lie one
    level up.
    """
    src = io.open(SRC, encoding="utf-8").read()
    blk = src[src.index("if a.recheck:"):src.index("if a.seed is not None:")]
    assert "unknown" in blk, "the --recheck summary does not mention unknowns"
    assert "could not be judged" in blk, "no human wording for the unknown count"
    return "the summary line reports unmeasured findings"


class FakeOracle:
    def __init__(self, name, arch=None):
        self.name, self.arch = name, arch


NATIVE = [FakeOracle("fpc-O0"), FakeOracle("pxx-O0"), FakeOracle("pxx-O3")]
CROSS = NATIVE + [FakeOracle("pxx-i386", "i386"), FakeOracle("pxx-aarch64", "aarch64"),
                  FakeOracle("pxx-arm32", "arm32")]


def t_oracle_gap_is_exact_when_recorded():
    m = load()
    e = {"oracles": ["fpc-O0", "pxx-O0", "pxx-aarch64"]}
    assert m.oracle_gap(e, NATIVE) == ["pxx-aarch64"], m.oracle_gap(e, NATIVE)
    assert m.oracle_gap(e, CROSS) == [], m.oracle_gap(e, CROSS)
    return "a recorded oracle set is compared exactly"


def t_oracle_gap_falls_back_for_legacy_entries():
    """Every entry filed before 2026-08-30 has no recorded oracle set. The real
    one that motivated this: a note reading "i386/aarch64/arm32 reject EVERY
    store through a pointer to a record that has a string[N] field".
    """
    m = load()
    e = {"sig": "pxx-reject_store-through-pointer-cross",
         "kind": "store-through-pointer",
         "note": "i386/aarch64/arm32 reject EVERY store through a pointer to a "
                 "record that has a string[N] field. Only bites --cross runs."}
    assert m.oracle_gap(e, NATIVE), "the legacy cross finding was judged native-only"
    assert m.oracle_gap(e, CROSS) == [], "a cross run should have no gap"
    return "a legacy cross finding is not judged by a native-only run"


def t_oracle_gap_leaves_ordinary_findings_alone():
    """The heuristic must not make every legacy entry unjudgeable — the fpc-self
    findings recheck correctly today and must keep doing so.
    """
    m = load()
    e = {"sig": "fpc-self_if", "kind": "if", "note": "FPC CONTRADICTS ITSELF (-O0 vs -O2)"}
    assert m.oracle_gap(e, NATIVE) == [], m.oracle_gap(e, NATIVE)
    return "a native finding is still judged by a native run"


def t_a_gap_can_only_produce_cannot_judge():
    """The heuristic's safety property, asserted rather than argued: an oracle
    gap must never mark an entry fixed. It errs toward "I did not manage to
    look", which is recoverable; erring toward "clean" is not.
    """
    m = load()
    led = {"version": 1, "findings": {"x": {
        "status": "dodged", "sig": "pxx-reject_cross-thing",
        "note": "aarch64 rejects it", "oracles": [],
        "examples": [{"seed": 5, "args": ["--seed", "5"]}]}}}
    m.evaluate = lambda o, src, wd: "chk"
    m.classify = lambda res: (False, None, None, "cls")   # would say FIXED
    m.emit = lambda a, w, sd, **kw: (0, "", "/x.pas")
    with tempfile.TemporaryDirectory() as wd:
        with Capture() as cap:
            fixed, still, unknown = m.recheck(led, NATIVE, wd, sha="d")
    assert (fixed, still, unknown) == (0, 0, 1), (fixed, still, unknown)
    assert led["findings"]["x"]["status"] == "dodged", "an oracle gap closed an entry"
    assert "CANNOT JUDGE" in cap.text, cap.text
    return "an oracle gap cannot produce a FIXED"


def t_new_findings_record_their_oracles():
    m = load()
    led = {"version": 1, "findings": {}}
    m.ledger_record(led, "s", "pxx-self", "case", 1, ["--seed", "1"], "n", "abc",
                    oracles=["fpc-O0", "pxx-aarch64"])
    assert led["findings"]["s"]["oracles"] == ["fpc-O0", "pxx-aarch64"], led
    return "a new finding records the oracle set that saw it"


TESTS = [t_pasmith_still_rejects_units_with_dash_o,
         t_recheck_regenerates_through_emit,
         t_recheck_walks_more_than_the_throttle_set,
         t_dodged_is_regenerated_with_dodges_off,
         t_pasmith_honours_the_dodge_override,
         t_oracle_gap_is_exact_when_recorded,
         t_oracle_gap_falls_back_for_legacy_entries,
         t_oracle_gap_leaves_ordinary_findings_alone,
         t_a_gap_can_only_produce_cannot_judge,
         t_new_findings_record_their_oracles,
         t_emit_uses_outdir_for_units,
         t_the_generator_command_line_exists_once,
         t_check_mode_goes_through_emit,
         t_check_mode_puts_the_source_dir_on_the_unit_path,
         t_localize_no_longer_duplicates_the_rule,
         t_multi_unit_example_is_judgeable,
         t_returns_three_counts,
         t_unmeasurable_is_not_reported_as_reproducing,
         t_unmeasurable_is_not_reported_as_fixed_either,
         t_unmeasurable_names_the_seed_and_the_reason,
         t_no_examples_is_unknown_not_fixed,
         t_genuine_reproduction_still_says_so,
         t_summary_line_surfaces_unknowns]


def main():
    bad = 0
    for t in TESTS:
        try:
            print("  ok   %-46s %s" % (t.__name__, t()))
        except Exception as e:
            bad += 1
            print("  FAIL %-46s %s" % (t.__name__, e))
    print("%s: %d/%d" % ("FAIL" if bad else "PASS", len(TESTS) - bad, len(TESTS)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
