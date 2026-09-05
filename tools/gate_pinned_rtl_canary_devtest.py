#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the pinned-RTL canary in gate.sh must be able to FAIL.

`make pin` freezes compiler/builtin/** into stable_linux_amd64/default/builtin/,
so from that moment the pinned compiler builds a FROZEN builtin set against a
LIVE lib/rtl. A Track A change that adds a builtin and calls it from lib/rtl is
coherent, reaches its self-host fixedpoint, and passes the whole quick gate --
and kills every $(PXX_STABLE) build the instant it lands. That is 97b1812fe:
`undefined variable (PXXNilRefHook)`, Tracks B/D/E dead on master until the next
pin, found by accident.

gate.sh grew a ~1s canary for it (bug-t-gate-quick-cannot-see-a-broken-pinned-rtl).
This guards the canary, and specifically guards the way it would rot:

  * **the fixture must exist.** The canary SKIPs when
    test/test_uses_sysutils.pas is absent, so a rename in another lane turns it
    into a permanent green that asserts nothing -- which is precisely the class
    of hole it was added to close. A SKIP is the right behaviour on a clone
    without a pin; a SKIP forever, in-repo, is the bug.
  * **it must go red on a real mismatch.** Built in a scratch tree, because the
    check has to be seen failing: a canary that has never failed is not yet a
    canary. Reproduces the original shape -- one reference in lib/rtl to a
    builtin the frozen set does not define.

Run: tools/gate_pinned_rtl_canary_devtest.py   (exit 0 = pass)
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE = os.path.join(REPO, "tools", "gate.sh")
FIXTURE = os.path.join(REPO, "test", "test_uses_sysutils.pas")
PIN = os.path.join(REPO, "stable_linux_amd64", "default", "pinned")
HOOKS = os.path.join(REPO, "lib", "rtl", "sysutils.pas")


def t_the_gate_still_has_the_canary():
    with open(GATE) as f:
        src = f.read()
    assert "pinned_rtl_canary" in src, "gate.sh lost the canary function"
    assert "pinned builds live lib/rtl" in src, "gate.sh lost the canary step"
    # Two questions, and the second is the one that would be dropped as
    # redundant: the compile asks whether the frozen builtin still satisfies
    # lib/rtl's references, the run asks whether the result works. A pinned RTL
    # that compiles and then dies is just as broken for Track B.
    fn = src.split("pinned_rtl_canary() {", 1)[1].split("\n}", 1)[0]
    # ASSERT THE BEHAVIOUR, NOT THE SPELLING. This row used to look for the
    # literal `"$bin"` -- the variable the canary happened to use. b6212f43f
    # rewrote the sweep and named its artifact `$work/run.bin`, so the guard
    # went RED while the canary still compiled AND ran exactly as before, and
    # `make tools-devtest` reported that the run step had been dropped when it
    # was sitting there under a new name. A text check cannot tell a renamed
    # variable from a deleted step; the fix is to ask the question the row
    # actually means -- does this function EXECUTE something it just built?
    built = sorted(set(re.findall(r'"\$pin(?:abs)?"[^\n]*?"(\$[^"]*\.bin)"',
                                  fn)))
    assert built, (
        "the canary compiles nothing -- no `\"$pinabs\" ... \"$x.bin\"` "
        "invocation found, so there is no artifact for it to run")
    ran = [b for b in built
           if re.search(r'^\s*"%s"' % re.escape(b), fn, re.M)]
    assert ran, (
        "the canary no longer RUNS the program it built -- it compiles %s and "
        "executes none of them, answering only half the question "
        "feature-t-gate-quick-should-smoke-the-pinned-compiler asked"
        % ", ".join(built))
    return ("gate.sh defines the canary, compiles AND runs (%s)"
            % ", ".join(ran))


def t_the_run_assertion_can_discriminate():
    """The row above went RED on a RENAME while the behaviour was intact, so
    the replacement has to be shown doing both halves: red when the run step is
    really gone, green when only the artifact's name moved.

    Controls are derived from the LIVE gate.sh rather than from a fixture --
    a control built from a hand-written string tests the regex against my
    idea of the file, which is the population the original assertion was
    already wrong about."""
    with open(GATE) as f:
        fn = f.read().split("pinned_rtl_canary() {", 1)[1].split("\n}", 1)[0]

    def ran(text):
        built = set(re.findall(r'"\$pin(?:abs)?"[^\n]*?"(\$[^"]*\.bin)"',
                               text))
        return [b for b in built
                if re.search(r'^\s*"%s"' % re.escape(b), text, re.M)]

    live = ran(fn)
    assert live, "precondition: the live canary must be running something"

    # POSITIVE CONTROL: the defect the row exists to catch. Drop the execution
    # while leaving every compile in place.
    cut = re.sub(r'^\s*"\$work/[^"]*\.bin"[^\n]*$', '  :', fn, flags=re.M)
    assert not ran(cut), (
        "the assertion cannot fail: with every execution line removed it still "
        "reports that the canary runs what it built")

    # NEGATIVE CONTROL: the false alarm of 2026-09-05. A rename must NOT be
    # reported as a deletion.
    renamed = fn.replace("run.bin", "smoke.bin")
    assert ran(renamed), (
        "renaming the artifact reads as deleting the run step -- this is the "
        "exact false RED that made `make tools-devtest` claim the canary had "
        "lost half its question while it was intact under a new name")

    return "red when the run is deleted, green when it is merely renamed"


def t_make_pin_verifies_the_binary_it_just_blessed():
    """The other end of the same seam. gate.sh catches the commit that breaks
    $(PXX_STABLE); this catches the PIN that fails to fix it -- taken while
    holding the repo-wide lock, which is the expensive moment to be wrong."""
    with open(os.path.join(REPO, "Makefile")) as f:
        mk = f.read()
    pin = mk.split("\npin:", 1)[1].split("\n\n", 1)[0]
    assert "PIN VERIFY FAILED" in pin, (
        "make pin no longer verifies that the binary it just blessed can "
        "build lib/rtl")
    assert "exit 1" in pin, (
        "the pin verification must FAIL the target -- the entire cost of this "
        "failure is that nobody looks, so a warning that scrolls past is the "
        "same as no check")
    return "make pin verifies the new pin against lib/rtl and exits 1"


def t_the_fixture_exists_so_the_skip_is_not_permanent():
    assert os.path.isfile(FIXTURE), (
        "%s is gone -- the canary SKIPs and gate.sh is green forever on a hole "
        "it was added to close" % os.path.relpath(FIXTURE, REPO))
    with open(FIXTURE) as f:
        body = f.read().lower()
    assert "uses sysutils" in body, (
        "the fixture no longer pulls sysutils, so it no longer crosses the "
        "frozen-builtin/live-lib seam it exists to test")
    return "fixture present and still crosses the seam"


def _scratch_tree(tmp):
    """A minimal repo-shaped tree the pinned compiler can run in.

    The compiler anchors its unit search at ExeDir/../lib/rtl, so the layout
    has to be reproduced rather than faked with flags.
    """
    os.makedirs(os.path.join(tmp, "default"))
    shutil.copy(os.path.realpath(PIN), os.path.join(tmp, "default", "pinned"))
    shutil.copytree(os.path.join(REPO, "stable_linux_amd64", "default",
                                 "builtin"),
                    os.path.join(tmp, "default", "builtin"))
    shutil.copytree(os.path.join(REPO, "lib", "rtl"),
                    os.path.join(tmp, "lib", "rtl"))
    return os.path.join(tmp, "default", "pinned")


def _compile(pinned, out):
    p = subprocess.run([pinned, FIXTURE, out], capture_output=True, text=True,
                       timeout=180)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def t_the_canary_is_green_on_a_sound_tree():
    if not os.path.exists(PIN):
        return "SKIP - no pinned binary in this checkout"
    with tempfile.TemporaryDirectory() as tmp:
        pinned = _scratch_tree(tmp)
        rc, out = _compile(pinned, os.path.join(tmp, "out"))
        assert rc == 0, "canary red on an UNMODIFIED tree: %s" % out[-400:]
    return "an untouched pin + lib/rtl compiles the fixture"


def t_the_canary_is_red_when_live_rtl_outruns_the_frozen_builtin():
    if not os.path.exists(PIN):
        return "SKIP - no pinned binary in this checkout"
    with tempfile.TemporaryDirectory() as tmp:
        pinned = _scratch_tree(tmp)
        sysutils = os.path.join(tmp, "lib", "rtl", "sysutils.pas")
        with open(sysutils) as f:
            lines = f.readlines()
        # Same shape as 97b1812fe: lib/rtl assigns a hook the frozen builtin
        # set does not define. Anchored on an existing hook assignment so the
        # insertion lands in a reachable statement position.
        for i, line in enumerate(lines):
            if "Hook := @" in line:
                lines.insert(i + 1,
                             "  PXXCanaryProofHook := @SysRaiseAccessViolation;\n")
                break
        else:
            raise AssertionError("no `...Hook := @` line in lib/rtl/sysutils.pas "
                                 "to anchor the injected mismatch on")
        with open(sysutils, "w") as f:
            f.writelines(lines)
        rc, out = _compile(pinned, os.path.join(tmp, "out"))
        assert rc != 0, (
            "the canary PASSED against a lib/rtl referencing a builtin the "
            "frozen set does not define -- it cannot catch 97b1812fe")
        assert "PXXCanaryProofHook" in out, (
            "canary failed, but not on the injected mismatch: %s" % out[-400:])
    return "reproduces the original `undefined variable` shape, exit %d" % rc


def main():
    rc = 0
    for fn in (t_the_gate_still_has_the_canary,
               t_the_run_assertion_can_discriminate,
               t_make_pin_verifies_the_binary_it_just_blessed,
               t_the_fixture_exists_so_the_skip_is_not_permanent,
               t_the_canary_is_green_on_a_sound_tree,
               t_the_canary_is_red_when_live_rtl_outruns_the_frozen_builtin):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("pinned-rtl canary OK" if rc == 0 else "pinned-rtl canary BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
