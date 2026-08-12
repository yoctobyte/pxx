#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: `testmgr --pin` applies the pin atomically, or not at all.

feature-t-testmgr-owns-pinning-interruptible. The ask was pinning that is
INTERRUPTIBLE: "SIGINT tears down cleanly, kills job process groups, and leaves
NO half-applied pin — either the pin completed or the tree is untouched."

`make pin` cannot promise that. It is four separate mutations — copy the binary,
move the `pinned` symlink, append pin.log, `rm -rf builtin` then repopulate it —
and an interrupt between any two leaves a pin nobody can reason about. The
`rm -rf` is the sharp one: interrupted there, the pinned compiler resolves
`uses builtin` against a directory that is empty or half-written, and every
$(PXX_STABLE) consumer silently builds against the wrong RTL. A red master is
cheap and recoverable; a bad pin poisons another lane for hours.

apply_pin_atomic() splits the work in two, and these are the invariants:

  * the whole new pin is staged OUTSIDE the live names, so an abort there is a
    deleted staging directory and nothing else — the tree is byte-identical;
  * the flip itself is renames only, under a signal mask, so a SIGINT arriving
    mid-flip is DEFERRED rather than delivered into the middle of it;
  * and it leaves no staging residue either way, because a `.pin-staging.NNN`
    left in the stable dir would end up staged by the `git add` that follows.

Run: tools/devtest_pin_atomic.py   (exit 0 = pass)
"""
import importlib.util
import os
import shutil
import signal
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm", os.path.join(HERE,
                                                                "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)


def build(root):
    """A miniature stable tree: old pin in place, new binary waiting."""
    d = os.path.join(root, "stable_linux_amd64", "default")
    os.makedirs(os.path.join(d, "builtin"))
    os.makedirs(os.path.join(root, "compiler", "builtin"))
    with open(os.path.join(d, "stable_latest"), "w") as f:
        f.write("NEW-BINARY")
    with open(os.path.join(d, "stable_pinned"), "w") as f:
        f.write("OLD-BINARY")
    os.symlink("stable_pinned", os.path.join(d, "pinned"))
    with open(os.path.join(d, "builtin", "stale.pas"), "w") as f:
        f.write("the RTL the OLD pin froze")
    with open(os.path.join(d, "VERSION"), "w") as f:
        f.write("41")
    with open(os.path.join(d, "pin.log"), "w") as f:
        f.write("# pin log\n")
    for n in ("builtin.pas", "builtinheap.pas"):
        with open(os.path.join(root, "compiler", "builtin", n), "w") as f:
            f.write("current RTL " + n)
    tm.REPO = root
    return d


def snap(d):
    return {"pinned": open(os.path.join(d, "pinned")).read(),
            "builtin": sorted(os.listdir(os.path.join(d, "builtin"))),
            "log": len(open(os.path.join(d, "pin.log")).readlines()),
            # anything dotted in the stable dir is staging residue
            "residue": sorted(x for x in os.listdir(d) if x.startswith("."))}


FRESH = ["builtin.pas", "builtinheap.pas"]


def t_applies(d):
    """The happy path actually swings every part of the pin."""
    before = snap(d)
    sha, n = tm.apply_pin_atomic(tm._pin_paths(), "d" * 40)
    a = snap(d)
    assert a["pinned"] == "NEW-BINARY", a
    assert a["builtin"] == FRESH, a          # stale.pas gone, both fresh in
    assert a["log"] == before["log"] + 1, a
    assert a["residue"] == [], a
    assert n == 2, n
    return "pinned swung, builtin replaced, log appended, no residue"


def t_abort_while_staging(d):
    """Interrupted before the flip: the tree must be untouched, not partial."""
    before = snap(d)
    real = shutil.copy2

    def boom(src, dst, **kw):
        if "builtin" in str(dst):           # part-way through staging
            raise KeyboardInterrupt("SIGINT while staging")
        return real(src, dst, **kw)

    shutil.copy2 = boom
    try:
        tm.apply_pin_atomic(tm._pin_paths(), "c" * 40)
        raise AssertionError("expected the interrupt to propagate")
    except KeyboardInterrupt:
        pass
    finally:
        shutil.copy2 = real
    after = snap(d)
    assert after == before, "%s != %s" % (after, before)
    return "tree byte-identical; nothing half-applied"


def t_sigint_during_flip(d):
    """The load-bearing one: a SIGINT raised INSIDE the critical section must
    not run there, and must still be delivered afterwards."""
    handled = []
    signal.signal(signal.SIGINT, lambda *a: handled.append("handled"))
    real = os.replace
    fired = []

    def replace_then_signal(a, b):
        r = real(a, b)
        if not fired:                       # exactly once, mid-flip
            fired.append(1)
            os.kill(os.getpid(), signal.SIGINT)
            assert not handled, "SIGINT ran INSIDE the critical section"
        return r

    os.replace = replace_then_signal
    try:
        tm.apply_pin_atomic(tm._pin_paths(), "f" * 40)
    finally:
        os.replace = real
        signal.signal(signal.SIGINT, signal.SIG_DFL)
    a = snap(d)
    assert handled == ["handled"], "signal never delivered: %r" % handled
    assert a["pinned"] == "NEW-BINARY" and a["builtin"] == FRESH, a
    assert a["residue"] == [], a
    return "SIGINT deferred past the flip, then delivered; pin complete"


def main():
    rc = 0
    for fn in (t_applies, t_abort_while_staging, t_sigint_during_flip):
        root = tempfile.mkdtemp(prefix="devtest-pinatomic-")
        try:
            d = build(root)
            note = fn(d)
            print("  ok   %s — %s" % (fn.__name__, note))
        except Exception as e:            # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s" % (fn.__name__, type(e).__name__, e))
        finally:
            shutil.rmtree(root, ignore_errors=True)
    print("atomic pin OK" if rc == 0 else "atomic pin BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
