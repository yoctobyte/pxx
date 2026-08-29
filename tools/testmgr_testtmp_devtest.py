#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: testmgr's scratch-root derivations must move together, or not at all.

Seven expressions used to hardcode the literal `/tmp` prefix as it appears in
`make -n` output, held together by nothing but a comment:

    "If anything ever runs make_dry_run() with TESTTMP set elsewhere, all four
     go blind AT ONCE and fail silently -- no privatization (concurrent runs
     collide again) and no producer/consumer merge (which is how
     test-core#555/#556 went red on 2026-07-12). Teach them the value before
     setting it; do not set it and hope."

Both halves of that failure are silent and both still produce a VERDICT, which
is why it needed a guard rather than a second comment: a collision-red and a
real defect read identically.

TWO PROPERTIES, and the first is what makes the change safe to land at all:

  * with TESTTMP UNSET every derived value is byte-identical to the literal it
    replaced, so today's behaviour is provably unchanged;
  * with TESTTMP SET they all move TOGETHER -- none is left matching the old
    root, which is the "go blind" state, and none matches a path outside the
    new root, which would privatize something a compiled source has baked in.

Run: tools/testmgr_testtmp_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = "/scratchroot"          # deliberately shares no substring with "/tmp"


def load(testtmp=None):
    """Import testmgr fresh under a chosen TESTTMP. -> module."""
    old = os.environ.get("TESTTMP")
    if testtmp is None:
        os.environ.pop("TESTTMP", None)
    else:
        os.environ["TESTTMP"] = testtmp
    try:
        spec = importlib.util.spec_from_file_location(
            "tm_%s" % (testtmp or "unset"), os.path.join(HERE, "testmgr.py"))
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        return m
    finally:
        if old is None:
            os.environ.pop("TESTTMP", None)
        else:
            os.environ["TESTTMP"] = old


# The exact text each expression had before the derivation. Written out rather
# than computed, so this guard cannot drift with the code it checks.
HISTORICAL = {
    "TMP_RE": r"/tmp(?![\w.-])(?:/[A-Za-z0-9_.+-]+)*",
    "_REASON_TMP_RE": r"/tmp/[A-Za-z0-9_./+-]+",
    "DRY_TMP_RE": r"/tmp/[A-Za-z0-9_./+-]+",
    "DRY_SO_PROD_RE": r"-o\s+/tmp/\S+\.so\b",
    "DRY_LOADER_DIR_RE": r"LD_LIBRARY_PATH=/tmp(?![\w./-])",
}


def t_unset_is_byte_identical_to_the_old_literals():
    """The whole basis for landing this: today does not change."""
    m = load(None)
    assert m.TESTTMP == "/tmp", m.TESTTMP
    for name, want in HISTORICAL.items():
        got = getattr(m, name).pattern
        assert got == want, \
            "%s drifted from its pre-derivation text:\n  got  %r\n  want %r" \
            % (name, got, want)
    assert m.RUN_TMP == "/tmp/testmgr-scratch-%d" % os.getpid(), m.RUN_TMP
    return "with TESTTMP unset, every derivation equals the old literal"


def t_all_of_them_move_together():
    """The 'go blind AT ONCE' state, asserted as its inverse.

    One expression left behind is exactly as bad as all of them: privatization
    and the producer/consumer merge each depend on their own regex matching.
    """
    m = load(ROOT)
    stale = [n for n in HISTORICAL if "/tmp" in getattr(m, n).pattern]
    assert not stale, \
        "these still match the OLD root while TESTTMP moved — they are blind " \
        "and silent: %s" % ", ".join(stale)
    assert m.RUN_TMP.startswith(ROOT + "/"), \
        "RUN_TMP stayed behind, so privatized output would land outside the " \
        "root the recipes name: %s" % m.RUN_TMP
    return "every derivation follows TESTTMP, none is left behind"


def t_a_bare_tmp_path_is_no_longer_a_recipe_path():
    """The other direction, and it is not symmetric.

    Once the recipes build elsewhere, a literal /tmp path in a recipe belongs
    to something else -- another tool, or a path a compiled source baked in.
    Privatizing it would point producer and consumer at different files, which
    is the defect pinned_tmp_paths() exists to prevent.
    """
    m = load(ROOT)
    assert not m.TMP_RE.search("cc -o /tmp/libfoo.so x.c"), \
        "a bare /tmp path would still be rewritten after the root moved"
    assert m.TMP_RE.search("cc -o %s/libfoo.so x.c" % ROOT), \
        "a path under the new root is not recognised at all"
    return "a bare /tmp path is left alone once the root moves"


def t_the_rewrite_stays_coherent():
    """Producer and consumer must land in the SAME private directory."""
    m = load(ROOT)
    line = ("cc -o %s/libfoo.so x.c && LD_LIBRARY_PATH=%s ./a.out"
            % (ROOT, ROOT))
    out = m.TMP_RE.sub(
        lambda mm: m.RUN_TMP + mm.group(0)[len(m.TESTTMP):], line)
    assert out.count(m.RUN_TMP) == 2, \
        "the .so and the loader path did not both land in RUN_TMP: %s" % out
    assert ROOT + "/lib" not in out, out
    return "the .so and its loader path land in one private directory"


def t_the_loader_directory_form_is_still_seen():
    """`LD_LIBRARY_PATH=<root>` names no filename — the merge depends on it.

    Missing it is how test-core#555/#556 went red on a freshly booted box and
    green wherever a stale library happened to survive.
    """
    m = load(ROOT)
    assert m.DRY_LOADER_DIR_RE.search("LD_LIBRARY_PATH=%s ./a.out" % ROOT)
    assert m.DRY_SO_PROD_RE.search("cc -o %s/libspill.so x.c" % ROOT)
    return "the .so producer and the bare-directory consumer are both matched"


def t_a_trailing_slash_is_normalised():
    m = load(ROOT + "/")
    assert m.TESTTMP == ROOT, m.TESTTMP
    assert "//" not in m.RUN_TMP, m.RUN_TMP
    return "a trailing slash does not produce a doubled separator"


def t_an_empty_value_falls_back_rather_than_matching_everything():
    """`TESTTMP=` must not compile to a regex that matches every path."""
    m = load("")
    assert m.TESTTMP == "/tmp", m.TESTTMP
    assert not m.TMP_RE.search("cc -o /home/user/x.so y.c"), \
        "an empty TESTTMP produced a pattern matching unrelated paths"
    return "an empty TESTTMP falls back to /tmp"


def t_the_root_is_regex_escaped():
    """A root with regex metacharacters must be a literal, not a pattern."""
    m = load("/tmp/a+b")
    assert m.TMP_RE.search("cc -o /tmp/a+b/x.so y.c"), \
        "a root containing `+` was treated as a quantifier"
    assert not m.TMP_RE.search("cc -o /tmp/aab/x.so y.c"), \
        "the root was interpreted as a regex rather than escaped"
    return "the root is regex-escaped, not interpolated raw"


TESTS = [t_unset_is_byte_identical_to_the_old_literals,
         t_all_of_them_move_together,
         t_a_bare_tmp_path_is_no_longer_a_recipe_path,
         t_the_rewrite_stays_coherent,
         t_the_loader_directory_form_is_still_seen,
         t_a_trailing_slash_is_normalised,
         t_an_empty_value_falls_back_rather_than_matching_everything,
         t_the_root_is_regex_escaped]


def main():
    rc = 0
    print("testmgr-testtmp devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("testmgr-testtmp OK" if rc == 0 else "testmgr-testtmp BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
