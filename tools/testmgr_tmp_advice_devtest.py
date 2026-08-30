#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the /tmp guard's advice works, and the guard can tell it was taken.

The guard told authors to read `$TESTTMP`. testmgr launches every job through an
environment ALLOWLIST -- `ENV_ALLOW` plus the prefixes PXX_/TESTMGR_/LC_/QEMU_ --
and TESTTMP is in neither, so the read returns nothing and the test takes its
fallback: `/tmp`, or `GetTempDir` which is `/tmp` when TMPDIR is unset. Exactly
the shared path the literal was rejected for. **Guard green, collision intact**,
and five sources are in that state because they followed the advice faithfully
(bug-t-the-hardcoded-tmp-guard-recommends-a-variable-testmgr-strips).

That is the failure this file exists to keep fixed, and it has a shape worth
naming: **a ratchet whose remedy does not remedy anything.** It goes green,
everyone believes the class is handled, and the collisions continue. So the
guards below are in two halves -- the advice must be right, and the guard must
be able to see whether it was taken. The second half is the one that was
missing; without it "no /tmp literal" and "isolates" are the same green.

READS, NOT MENTIONS. `isolates()` looks for the accessor call, so a comment
explaining the rule neither satisfies nor breaks the check -- which matters
because the worked example discusses both variables at length directly above the
code that reads them, and a mention-based test would fail the one file that is
right.

Run: python3 tools/testmgr_tmp_advice_devtest.py
"""

import os
import pathlib
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr_hardcoded_tmp_devtest as g  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-58s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


PASCAL_BAD = """program p;
begin
  dir := GetEnvironmentVariable('TESTTMP');
  if dir = '' then dir := '/tmp';
end."""
PASCAL_GOOD = """program p;
begin
  dir := GetEnvironmentVariable('TESTMGR_TMP');
  if dir = '' then dir := GetEnvironmentVariable('TESTTMP');
  if dir = '' then dir := GetTempDir;
end."""
C_BAD = 'const char *d = getenv("TESTTMP"); if (!d) d = "/tmp";'
C_GOOD = ('const char *d = getenv("TESTMGR_TMP");\n'
          'if (!d) d = getenv("TESTTMP");\nif (!d) d = "/tmp";')
NPY_BAD = "d = os.environ.get('TESTTMP') or '/tmp'"
NPY_GOOD = "d = os.environ.get('TESTMGR_TMP') or os.environ.get('TESTTMP') or '/tmp'"
COMMENT_ONLY = """{ This file explains TESTMGR_TMP and TESTTMP at length and
  reads neither of them, because it has no scratch file. }
program p; begin writeln('hi'); end."""


def main():
    print("1. reads are found in source order, in all three languages")
    check(g.tmp_env_reads(PASCAL_GOOD) == ["TESTMGR_TMP", "TESTTMP"], "Pascal")
    check(g.tmp_env_reads(C_GOOD) == ["TESTMGR_TMP", "TESTTMP"], "C")
    check(g.tmp_env_reads(NPY_GOOD) == ["TESTMGR_TMP", "TESTTMP"], "NilPy/Python")
    check(g.tmp_env_reads(PASCAL_BAD) == ["TESTTMP"], "and the wrong order shows as one read")

    print("2. a MENTION is not a read")
    check(g.tmp_env_reads(COMMENT_ONLY) == [],
          "prose naming both variables reads neither")
    check(g.isolates(COMMENT_ONLY),
          "so a file with no scratch file is not accused of anything")

    print("3. isolates() is about ORDER, which is what the allowlist took away")
    for name, txt in (("Pascal", PASCAL_GOOD), ("C", C_GOOD), ("NilPy", NPY_GOOD)):
        check(g.isolates(txt), "%s: TESTMGR_TMP first -> isolates" % name)
    for name, txt in (("Pascal", PASCAL_BAD), ("C", C_BAD), ("NilPy", NPY_BAD)):
        check(not g.isolates(txt), "%s: TESTTMP first -> does NOT isolate" % name)

    print("4. the ratchet list is honest about the tree")
    for rel in sorted(g.KNOWN_ENV_ONLY):
        p = ROOT / rel
        check(p.exists(), "%s still exists (a dead entry is silent slack)" % rel)
    check(all(v.strip() for v in g.KNOWN_ENV_ONLY.values()),
          "every entry names the lane that owns the fix")

    print("5. the worked example really is one")
    ex = ROOT / "test/test_nilpy_class_named_like_an_rtl_record.npy"
    check(ex.exists(), "the file the advice points at exists")
    if ex.exists():
        txt = ex.read_text(errors="replace")
        check(g.tmp_env_reads(txt)[:1] == ["TESTMGR_TMP"],
              "and it reads TESTMGR_TMP first", str(g.tmp_env_reads(txt)))
        check(str(ex.relative_to(ROOT)) not in g.KNOWN_ENV_ONLY,
              "so it is not on the ratchet list")

    print("6. the advice itself -- this is the half that was wrong")
    a = g.ADVICE
    check(a.index("TESTMGR_TMP") < a.index("TESTTMP"),
          "TESTMGR_TMP is recommended before TESTTMP")
    for lang, needle in (("Pascal", "GetEnvironmentVariable('TESTMGR_TMP')"),
                         ("C", 'getenv("TESTMGR_TMP")'),
                         ("NilPy", "os.environ.get('TESTMGR_TMP')")):
        check(needle in a, "%s: the example is copy-pasteable" % lang)
    check("allowlist" in a and "does not reach the job" in a,
          "and it says WHY, so the order is not folklore")
    check("test/test_nilpy_class_named_like_an_rtl_record.npy" in a,
          "and points at the worked example")

    print("\n  %d guard(s), %d FAIL" % (23, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
