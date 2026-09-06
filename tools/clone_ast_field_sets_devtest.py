#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the CloneAST/AllocNode field-set check can actually fail.

Every branch runs against a SCRATCH arena built to make it fire. The live file
passes today, so a suite that only ran the real thing would print OK for a
checker that had been broken since it was written -- which is the same shape as
the docstring that hid the two missing slots in the first place: a sentence
asserting completeness, believed because nothing contradicted it.

The controls are the real defect, not a synthetic one. Case two deletes exactly
the line that was missing on 2026-09-06 (`ASTSemId`), and case three deletes
both that and its sibling (`ASTCLongRank`), because the original bug was two
omissions at once and a guard that stops at the first is a guard that finds
half of the next one.

Run: tools/clone_ast_field_sets_devtest.py   (exit 0 = pass)
"""
import importlib.util
import io
import os
import sys
import tempfile
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ARENA = os.path.join(ROOT, "compiler", "ast_arena.inc")


def _mod():
    spec = importlib.util.spec_from_file_location(
        "cafs", os.path.join(HERE, "clone_ast_field_sets.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _run(m, path):
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = m.main(["--file", path])
    return rc, buf.getvalue()


def _scratch(transform):
    """The live arena with one edit applied. -> path."""
    src = open(ARENA).read()
    fd, path = tempfile.mkstemp(suffix=".inc")
    os.close(fd)
    open(path, "w").write(transform(src))
    return path


def _drop(*names):
    def t(src):
        keep = [ln for ln in src.split("\n")
                if not any("%s[Result]" % n in ln for n in names)]
        return "\n".join(keep)
    return t


def t_the_live_arena_passes():
    rc, out = _run(_mod(), ARENA)
    assert rc == 0, "the real ast_arena.inc must pass: %s" % out
    assert "none missing" in out, out
    return "the tree as it stands is in sync"


def t_the_real_2026_09_06_omission_is_named():
    """ASTSemId, the slot that was actually missing."""
    p = _scratch(_drop("ASTSemId"))
    rc, out = _run(_mod(), p)
    assert rc == 1, "a missing slot must fail: %s" % out
    assert "ASTSemId" in out, out
    return "the slot that was really missing is reported by name"


def t_BOTH_omissions_are_named_not_just_the_first():
    """The original bug was two at once. A guard that reports one and stops
    hands its reader a repair that leaves the tree still broken, and the second
    omission was found only because someone kept looking after the first."""
    p = _scratch(_drop("ASTSemId", "ASTCLongRank"))
    rc, out = _run(_mod(), p)
    assert rc == 1, out
    assert "ASTSemId" in out and "ASTCLongRank" in out, \
        "both omissions must be listed, got: %s" % out
    return "two simultaneous omissions are both listed"


def t_a_payload_slot_is_NOT_excused():
    """ASTLeft is special -- cloned or copied per ASTLeftIsChild -- and is
    deliberately absent from CARRIED_OTHERWISE. If it were excused, a CloneAST
    that dropped the payload handling entirely would pass."""
    p = _scratch(_drop("ASTLeft"))
    rc, out = _run(_mod(), p)
    assert rc == 1, "dropping ASTLeft must fail, not be excused: %s" % out
    assert "ASTLeft" in out, out
    return "a payload slot is checked, not exempted for being special"


def t_a_stale_exception_is_refused():
    """An exception kept past its subject stops covering what it was written
    for and starts hiding whatever takes the name next."""
    m = _mod()
    m.CARRIED_OTHERWISE = dict(m.CARRIED_OTHERWISE)
    m.CARRIED_OTHERWISE["ASTNoSuchSlot"] = "a reason that outlived its field"
    rc, out = _run(m, ARENA)
    assert rc == 1, "an exception naming no live field must fail: %s" % out
    assert "ASTNoSuchSlot" in out, out
    return "an exception whose slot is gone is refused, not ignored"


def t_a_routine_it_cannot_find_is_NOT_a_pass():
    """The third state. A check that reports success by not running is the
    defect this whole family exists to remove, so it exits 2, never 0."""
    p = _scratch(lambda s: s.replace("function CloneAST(node: Integer): Integer;",
                                     "function CloneASTRenamed(node: Integer): Integer;"))
    rc, out = _run(_mod(), p)
    assert rc == 2, "a missing routine must be 2, not %d: %s" % (rc, out)
    assert "CANNOT SCOPE" in out and "not a pass" in out, out
    return "a renamed routine says so instead of passing"


TESTS = [t_the_live_arena_passes,
         t_the_real_2026_09_06_omission_is_named,
         t_BOTH_omissions_are_named_not_just_the_first,
         t_a_payload_slot_is_NOT_excused,
         t_a_stale_exception_is_refused,
         t_a_routine_it_cannot_find_is_NOT_a_pass]


def main():
    rc = 0
    print("clone-ast-field-sets devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("clone-ast-field-sets OK" if rc == 0 else "clone-ast-field-sets BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
