#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a test run by two targets must assert the same thing in both.

111 `.npy` sources are compiled and asserted by BOTH `test-nilpy` and
`test-core`, with the expectation written out VERBATIM in each -- often a
30-element `printf '%b'` string. The two copies sit thousands of lines apart, so
nothing about editing one suggests the other exists, and the half that goes red
is the `test-core` one, which the per-fix loop does not run. The edit is silent
at edit time and red in a target nobody runs until Track T's sweep, many commits
later.

Measured drift today is ZERO, which is what decides the shape: this is a
RATCHET on a clean invariant, not a report that arrives with a backlog and
teaches everyone to scroll past it. It fires on the first divergence.

WHAT IS COMPARED, and the keying is the whole subtlety. Not the expect_same
LABEL -- its `.1`/`.2` suffix is a sequence number WITHIN a target, not a copy
index, so grouping by it reports 91 false differences (two assertions about one
binary read as two copies of one assertion). Not the TESTTMP binary name either
-- 15 of those are written by two different sources. The key is the SOURCE FILE,
and the value is the ordered sequence of expectations attributed to it: every
`expect_same.sh` payload between its compile line and the next one.

Run: tools/npy_cross_target_expectation_devtest.py   (exit 0 = pass)
"""
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAKEFILE = os.path.join(REPO, "Makefile")

TARGET_RE = re.compile(r"^([A-Za-z0-9_][A-Za-z0-9_./%-]*)\s*:(?!=)")
COMPILE_RE = re.compile(
    r"\$\(COMPILER\)\s.*?(test/[A-Za-z0-9_./-]+\.(?:npy|pas|c))\s+"
    r"\$\(TESTTMP\)/([A-Za-z0-9_.-]+)")

# The 15 TESTTMP binary names two different sources both write. FROZEN, not
# ratcheted at zero: they exist today, they are safe only because the recipes
# that share a name run in order within one target, and the point of the freeze
# is that a SIXTEENTH cannot be added without someone reading this. The wider
# hazard -- 117 binaries written from more than one TARGET, which testmgr may
# run concurrently in one scratch root -- is
# bug-t-a-testtmp-binary-name-is-shared-by-two-tests-and-by-two-targets.
KNOWN_NAME_COLLISIONS = {
    "test_enumid26", "test_nilpy_boolop26", "test_nilpy_clsattr26",
    "test_nilpy_defshadow26", "test_nilpy_fromkeys26",
    "test_nilpy_genexprarg26", "test_nilpy_is_identity26",
    "test_nilpy_linecont26", "test_nilpy_mcall26", "test_nilpy_minmax26",
    "test_nilpy_nestcomp26", "test_nilpy_roundint26", "test_nilpy_str_repeat26",
    "test_nilpy_striter26", "test_nilpy_subdunder26",
}


def shell_words(s):
    """Split a recipe line, treating a double-quoted run as one word.

    Single quotes inside a double-quoted run are literal -- `printf '%b' '...'`
    is the normal shape here -- so tracking `"` and backslash is enough.
    """
    out, cur, quoted, i = [], "", False, 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            cur += s[i:i + 2]
            i += 2
            continue
        if c == '"':
            quoted = not quoted
            cur += c
            i += 1
            continue
        if c.isspace() and not quoted:
            if cur:
                out.append(cur)
                cur = ""
            i += 1
            continue
        cur += c
        i += 1
    if cur:
        out.append(cur)
    return out


def scan():
    """(target, source) -> [(line, payload), ...], and binary -> {source}."""
    blocks = collections.defaultdict(list)
    produced = collections.defaultdict(set)
    target = source = None
    with open(MAKEFILE, errors="replace") as f:
        for n, ln in enumerate(f.read().splitlines(), 1):
            if not ln.startswith("\t"):
                m = TARGET_RE.match(ln)
                if m:
                    target, source = m.group(1), None
                continue
            if target is None:
                continue
            body = ln.strip()
            m = COMPILE_RE.search(body)
            if m:
                source = m.group(1)
                produced[m.group(2)].add(source)
                blocks.setdefault((target, source), [])
                continue
            if "expect_same.sh" in body and source:
                w = shell_words(body)
                try:
                    k = w.index("tools/expect_same.sh")
                except ValueError:
                    continue
                args = w[k + 1:]
                if len(args) >= 3:
                    blocks[(target, source)].append((n, args[-1]))
    return blocks, produced


BLOCKS, PRODUCED = scan()
BY_SOURCE = collections.defaultdict(dict)
for (_t, _s), _v in BLOCKS.items():
    BY_SOURCE[_s][_t] = _v
MULTI = {s: t for s, t in BY_SOURCE.items() if s.endswith(".npy") and len(t) > 1}


def t_the_population_is_still_there():
    """A parse that silently stops matching reports zero drift forever.

    This is the guard on the INSTRUMENT, and it is the one that matters most:
    every other check below is a negative, and a negative is worthless from a
    scanner that found nothing to check."""
    assert len(BLOCKS) > 2000, \
        "only %d (target, source) blocks parsed — the Makefile scan broke" % len(BLOCKS)
    assert len(MULTI) >= 100, (
        "only %d .npy sources found in more than one target; there were 111. A "
        "drop this large means the scan stopped matching, not that tests were "
        "removed" % len(MULTI))
    payloads = sum(len(v) for v in BLOCKS.values())
    assert payloads > 2000, \
        "only %d expectations attributed to a compile — the scan broke" % payloads
    return "%d blocks, %d cross-target .npy sources, %d expectations" % (
        len(BLOCKS), len(MULTI), payloads)


def t_no_cross_target_expectation_drift():
    """THE ratchet. Zero today; fires on the first divergence."""
    drift = []
    for src, per_target in sorted(MULTI.items()):
        seqs = {t: tuple(p for _, p in v) for t, v in per_target.items()}
        if len(set(seqs.values())) > 1:
            where = "; ".join("%s:%s" % (t, [n for n, _ in v])
                              for t, v in sorted(per_target.items()))
            drift.append("%s (%s)" % (src, where))
    assert not drift, (
        "%d test source(s) assert different things in different targets. The "
        "expectation is written verbatim in each and the copies are thousands "
        "of lines apart, so an edit to one leaves the other red in a target the "
        "per-fix loop does not run:\n  %s" % (len(drift), "\n  ".join(drift)))
    return "%d sources asserted identically in every target" % len(MULTI)


def t_no_new_binary_name_collision():
    """Frozen at 15. A sixteenth means two tests overwrite each other's binary."""
    collisions = {b for b, s in PRODUCED.items() if len(s) > 1}
    new = collisions - KNOWN_NAME_COLLISIONS
    assert not new, (
        "%d NEW $(TESTTMP) binary name(s) written by two different sources: %s. "
        "Two tests compiling to one path overwrite each other, and the loser's "
        "assertion then runs the winner's program. Give it its own name."
        % (len(new), ", ".join(sorted(new))))
    gone = KNOWN_NAME_COLLISIONS - collisions
    assert not gone, (
        "%d frozen collision(s) are gone — good, but the list must shrink with "
        "them or it stops meaning anything: %s" % (len(gone), ", ".join(sorted(gone))))
    return "%d known collisions, none new" % len(collisions)


TESTS = [t_the_population_is_still_there,
         t_no_cross_target_expectation_drift,
         t_no_new_binary_name_collision]


def main():
    bad = 0
    for t in TESTS:
        try:
            print("  ok   %-40s %s" % (t.__name__, t()))
        except Exception as e:  # noqa: BLE001
            bad += 1
            print("  FAIL %-40s %s" % (t.__name__, fail_detail(e)))
    print("  %d guard(s), %d red" % (len(TESTS), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
