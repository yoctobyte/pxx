#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the watcher must not wedge itself with its own tstate writes.

The per-cycle dirty guard pauses when the clone is dirty, which is right for a
human's edit and right for dev sources leaking into a run. It is wrong for
`tstate/`, because that is face 1's ENTIRE write scope and nothing else on the
box writes there — so pausing on tstate dirt means waiting for a commit that
only the paused daemon could make. Deadlock.

That has now happened twice, from two different call sites:

  * 2026-07-11 — the `last_opt` bookkeeping did a bare save_state().
  * 2026-08-12 — mark_infra() did the same. A full tier ran GREEN 2293/2293,
    testmgr returned rc=2, and the infra record written to explain that was
    never committed. The box went dark for 16 HOURS, logging one
    "clone dirty — pausing this cycle" line per cycle, while systemd reported a
    perfectly healthy unit: active/running, NRestarts=0. Nothing about a hung
    daemon trips Restart=on-failure.

Both were fixed at the call site. This tests the SHAPE instead, so a third
bare save_state from some future path self-heals rather than taking the box
dark. Invariants:

  * tstate-only dirt is published, not paused on;
  * dirt outside tstate/ is left strictly alone, so the guard still protects a
    dev editing this checkout;
  * MIXED dirt publishes NOTHING. This one is safety, not tidiness: publish()
    recovers from a rebase conflict with _drop_to_origin(), a `reset --hard`
    that would take a human's uncommitted edit with it. publish() used to be
    reachable only after the guard proved the tree clean; running before the
    guard removes that protection unless mixed dirt suppresses it.

Run: tools/devtest_wedge_on_own_writes.py   (exit 0 = pass)
"""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE,
                                                                "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

SRC = "compiler/thing.pas"
TS = tw.TSTATE_REL + "/plexus.json"


def git(*a, cwd):
    return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True,
                          text=True)


def build(root):
    """A clone with a real origin, one tstate file and one source file."""
    origin = os.path.join(root, "origin.git")
    clone = os.path.join(root, "clone")
    git("init", "-q", "--bare", origin, cwd=root)
    git("clone", "-q", origin, clone, cwd=root)
    git("config", "user.email", "devtest@local", cwd=clone)
    git("config", "user.name", "devtest", cwd=clone)
    os.makedirs(os.path.join(clone, tw.TSTATE_REL))
    os.makedirs(os.path.join(clone, "compiler"))
    write(clone, TS, '{"host": "plexus"}')
    write(clone, SRC, "the platonic source")
    git("add", "-A", cwd=clone)
    git("commit", "-qm", "base", cwd=clone)
    git("push", "-q", "origin", "HEAD:master", cwd=clone)
    c = tw.Clone.__new__(tw.Clone)
    c.path, c.branch, c.remote = clone, "master", None
    c.host = None
    return c


def write(root, rel, text):
    with open(os.path.join(root, rel), "w") as f:
        f.write(text)


def dirty(c):
    return git("status", "--porcelain", "-uno", cwd=c.path).stdout.strip()


def t_publishes_own(c):
    """tstate-only dirt: the wedge case. Must end clean."""
    write(c.path, TS, '{"infra": {"count": 1}}')
    assert dirty(c), "setup failed"
    c.publish_own_writes("plexus")
    assert dirty(c) == "", "still dirty: %r" % dirty(c)
    return "published; next cycle would run instead of pausing"


def t_leaves_source_alone(c):
    """A dev editing this checkout must still stop the watcher."""
    write(c.path, SRC, "a dev edit, mid-run")
    before = dirty(c)
    moved = c.publish_own_writes("plexus")
    assert moved == [], moved
    assert dirty(c) == before, "%r != %r" % (dirty(c), before)
    return "untouched; the guard still pauses on it"


def t_mixed_publishes_nothing(c):
    """The safety case: never invoke publish() with a human's edit present."""
    write(c.path, SRC, "a dev edit, mid-run")
    write(c.path, TS, '{"infra": {"count": 2}}')
    before = dirty(c)
    moved = c.publish_own_writes("plexus")
    assert moved == [], moved
    assert dirty(c) == before, "tree altered: %r != %r" % (dirty(c), before)
    assert SRC in dirty(c), "the dev edit was destroyed"
    return "nothing published, dev edit intact, falls through to pause"


def diverge(c):
    """Commit a CHANGE to both tracked files and return the previous sha.

    Checking out the sha you are already on never conflicts, whatever is dirty
    -- git only refuses when the checkout would overwrite a local change. So a
    genuine reproduction needs a target whose content for that path differs.
    """
    base = git("rev-parse", "HEAD", cwd=c.path).stdout.strip()
    write(c.path, TS, '{"host": "plexus", "gen": 2}')
    write(c.path, SRC, "the platonic source, revised")
    git("add", "-A", cwd=c.path)
    git("commit", "-qm", "second", cwd=c.path)
    return base


def t_checkout_survives_a_write_made_after_the_heal(c):
    """The 2026-09-07 wedge: dirt appears BETWEEN the heal and the checkout.

    publish_own_writes() runs at the top of the cycle; note_idle_tier_try()
    then writes seven.json and only then does the cycle check out the sha. git
    refuses to move the worktree over it, identically every cycle -- so the
    "self-heals on the next cycle" promise does not hold for this shape, and
    the box goes dark instead of pausing."""
    base = diverge(c)
    c.publish_own_writes("plexus")          # top of cycle: tree is clean
    write(c.path, TS, '{"last_idle_tier_try": {"date": "later"}}')
    assert dirty(c), "setup failed: the post-heal write did not dirty the tree"
    c.host = "plexus"
    c.checkout(base)                        # must not raise
    assert dirty(c) == "", "still dirty after checkout: %r" % dirty(c)
    return "our own post-heal write is published and the checkout proceeds"


def t_checkout_still_refuses_a_dev_edit(c):
    """The tolerance must not become a bulldozer: a human's edit still stops
    the checkout, and is still intact afterwards."""
    base = diverge(c)
    write(c.path, SRC, "a dev edit, mid-run")
    c.host = "plexus"
    try:
        c.checkout(base)
        raise AssertionError("checkout ran over a dev edit")
    except RuntimeError:
        pass                                # git refused, which is correct
    assert SRC in dirty(c), "the dev edit was destroyed: %r" % dirty(c)
    return "a dev edit still refuses, and survives"


def t_checkout_without_a_host_keeps_the_old_behaviour(c):
    """Devtests and one-shot tools construct a Clone without a host. They must
    get the strict checkout, not a silent publish to origin."""
    base = diverge(c)
    write(c.path, TS, '{"whatever": 1}')
    before = dirty(c)
    c.host = None
    try:
        c.checkout(base)
        raise AssertionError("checkout published tstate dirt with no host set")
    except RuntimeError:
        pass
    assert dirty(c) == before, "tree altered without a host: %r" % dirty(c)
    return "no host set: strict, publishes nothing"


def main():
    rc = 0
    for fn in (t_publishes_own, t_leaves_source_alone,
               t_mixed_publishes_nothing,
               t_checkout_survives_a_write_made_after_the_heal,
               t_checkout_still_refuses_a_dev_edit,
               t_checkout_without_a_host_keeps_the_old_behaviour):
        root = tempfile.mkdtemp(prefix="devtest-wedge-")
        try:
            note = fn(build(root))
            print("  ok   %s — %s" % (fn.__name__, note))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s" % (fn.__name__, type(e).__name__, fail_detail(e)))
        finally:
            shutil.rmtree(root, ignore_errors=True)
    print("self-wedge protection OK" if rc == 0 else "self-wedge protection BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
