#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for the stale-seed guard (task-t-seed-from-stable-defeats-rebuild).

`make seed-from-stable` COPIES `stable_linux_amd64/default/pinned` onto
`compiler/pascal26`. The copy gets a fresh mtime, newer than
`compiler/compiler.pas`, so `make compiler/pascal26` reports "up to date" and no
self-host build happens — the entire sweep tests the PINNED binary instead of a
compiler built from the checked-out sources. Measured on xeon at 110774a14648:
byte-identical to pinned, mtime 13 minutes newer than the sources, 17 jobs red.

It is not only a first-run problem. It persists for every sha whose diff does
not touch a compiler source, because nothing bumps a source mtime past the
binary — which is a concrete mechanism for the phantom-NEW-RED family: red
against a stale compiler, then "fixed" at the next commit that happens to touch
compiler/**, with nothing in the range able to explain either transition.

The invariant under test: never run the matrix against a binary that IS the
pinned seed. Temp dirs only; the real repo is never touched.
Run: python3 tools/testmgr_unseed_devtest.py
"""
import os
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import testmgr  # noqa: E402
from devtest_report import fail_detail  # noqa: E402

FRESH = 1785700000          # any mtime a `cp` would leave: newer than sources


def fake_repo(tmp, compiler_bytes, pinned_bytes):
    """A checkout-shaped tree with just the two files the guard compares."""
    root = pathlib.Path(tmp)
    (root / "compiler").mkdir(parents=True)
    (root / "stable_linux_amd64" / "default").mkdir(parents=True)
    comp = root / testmgr.COMPILER
    if compiler_bytes is not None:
        comp.write_bytes(compiler_bytes)
        os.utime(comp, (FRESH, FRESH))
    if pinned_bytes is not None:
        (root / testmgr.PINNED_REL).write_bytes(pinned_bytes)
    return root, comp


def run_guard(tmp, compiler_bytes, pinned_bytes):
    root, comp = fake_repo(tmp, compiler_bytes, pinned_bytes)
    old_repo = testmgr.REPO
    testmgr.REPO = str(root)
    try:
        fired = testmgr.unseed_pinned()
    finally:
        testmgr.REPO = old_repo
    mtime = comp.stat().st_mtime if comp.exists() else None
    return fired, mtime


def case_seeded_binary_is_backdated():
    with tempfile.TemporaryDirectory() as tmp:
        fired, mtime = run_guard(tmp, b"PINNED-BYTES", b"PINNED-BYTES")
    assert fired, "guard did not fire on a binary identical to pinned"
    assert mtime == 0, f"binary not backdated (mtime {mtime}) — make would " \
                       f"still call it up to date"
    return "identical -> backdated to the epoch"


def case_real_build_is_left_alone():
    """The guard must be invisible on every normal run — it fires on identity,
    not on suspicion."""
    with tempfile.TemporaryDirectory() as tmp:
        fired, mtime = run_guard(tmp, b"A-REAL-SELFHOST-BUILD", b"PINNED-BYTES")
    assert not fired, "guard fired on a genuinely built compiler"
    assert mtime == FRESH, f"a real build's mtime was touched ({mtime})"
    return "different -> untouched"


def case_same_size_different_bytes():
    """Compared by content hash, not by size — a same-size build is a build."""
    with tempfile.TemporaryDirectory() as tmp:
        fired, _ = run_guard(tmp, b"AAAAAAAAAAAA", b"BBBBBBBBBBBB")
    assert not fired
    return "same size, different content -> untouched"


def case_missing_stable_tree_is_not_an_error():
    """A checkout without the stable tree (or without a built compiler yet)
    must fall through quietly rather than crash the run."""
    with tempfile.TemporaryDirectory() as tmp:
        fired, _ = run_guard(tmp, b"BUILD", None)
    assert not fired
    with tempfile.TemporaryDirectory() as tmp:
        fired, _ = run_guard(tmp, None, b"PINNED")
    assert not fired
    return "missing pinned / missing compiler -> no-op"


CASES = [
    case_seeded_binary_is_backdated,
    case_real_build_is_left_alone,
    case_same_size_different_bytes,
    case_missing_stable_tree_is_not_an_error,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = case()
        except AssertionError as e:
            print(f"  FAIL {name}: {fail_detail(e)}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("stale-seed guard OK" if rc == 0 else "stale-seed guard BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
