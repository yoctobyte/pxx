#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: an absent host DEV LIBRARY must SKIP the job, never redden it.

Third face of one guard -- silicon (HOST_CAPS), $PATH (host tools), and now the
filesystem's development headers. A red asserts "the tree is broken"; a skip
says "this was not measured here". Only the second is true when a package is
missing, and the difference has a price tag.

MEASURED 2026-09-05: seven's dist-upgrade REMOVED libgtk2.0-dev and libgtk-3-dev
(installed 08-29, gone during 15:20-17:30, reinstalled by hand 17:59:31). Five
test-core jobs went red at 17:58:11 and auto-filed at 17:58:16, seventy-five
seconds before the reinstall. That was the FOURTH batch wearing those same five
test names -- eighteen tickets in all, over four different mechanisms, and the
other three were real defects since fixed. Folding them together would have
erased two genuine fixes.

WHAT THIS GUARDS, and the second row is the one that nearly shipped broken:

1. **It can fire at all.** A skip path that never triggers is the guard that
   cannot fail, and it prints nothing rather than PASS -- quieter still.

2. **IT DOES NOT FIRE WHEN THE UNIT RESOLVES.** The compiler tries
   `/usr/include/<name>.h` AND `/usr/include/gtk-2.0/gtk/<name>.h`, in that
   order; frankD's strace shows the first missing and the second opening. A
   guard checking only the first declares the dependency absent while the unit
   resolves perfectly -- a FALSE SKIP, which is strictly worse than the false
   red it replaces, because a red is loud and a skip is silent. Caught here
   before it landed, by reading the roots and finding TWO.

3. **The roots are DERIVED from the compiler, not restated.** A guard carrying
   its own copy drifts the moment the compiler moves one, and then probes a
   path nothing uses and passes every job forever.

4. **The population is not one flag.** Four packages across three profiles:
   three tests want libgtk2.0-dev at build time; test_c_gtk_window wants that
   plus a GTK runtime plus xvfb-run; test_c_gtk3_stock wants libgtk-3-dev via
   an explicit -I. A single HOST_LIBS list would merge conditions that are not
   the same condition, which is how the batch reached eighteen.

Run: python3 tools/host_dev_lib_skip_devtest.py
"""

import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location(
    "tm", os.path.join(ROOT, "tools", "testmgr.py"))
tm = importlib.util.module_from_spec(_spec)
try:
    _spec.loader.exec_module(tm)
except SystemExit:
    pass

fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                  # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-58s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def job(*lines):
    j = tm.Job("t", 0, list(lines))
    j.status = "run"
    return j


def main():
    print("1. the search roots are read from the compiler, and still match")
    roots = tm.uses_fallback_roots()
    check(roots, "pasparser_proc.inc's fallbacks are readable",
          "found %d: %s" % (len(roots), ", ".join(roots)) if roots else
          "NONE — the parse stopped matching, and a guard with no roots "
          "silently checks nothing")
    check(any("gtk-2.0" in r for r in roots),
          "and the gtk-2.0 arm is among them",
          "this is the arm frankD's strace showed actually opening")
    check(len(roots) >= 2,
          "MORE THAN ONE — the resolver falls through in order",
          "checking only the first is the false-skip bug this file exists for")

    print("2. it fires when the header is genuinely absent")
    gtk = job("./$(COMPILER) test/test_c_gtk.pas $(TESTTMP)/x")
    got = tm.missing_dev_requirement(gtk, ["/nonexistent-a/", "/nonexistent-b/"])
    check(got and got[0].endswith("gtk.h"),
          "a `uses gtk` job with no header anywhere is flagged", str(got))

    print("3. AND NOT when the unit resolves — the false-skip control")
    # The real roots on this box. If this fires, the guard would SKIP jobs that
    # compile perfectly, and nobody would see it: a skip is silent.
    live = tm.missing_dev_requirement(gtk, roots)
    check(live is None or not os.path.exists("/usr/include/gtk-2.0/gtk/gtk.h"),
          "not flagged while the header is present on this box",
          "live=%s (header present=%s)"
          % (live, os.path.exists("/usr/include/gtk-2.0/gtk/gtk.h")))
    # ...and the ordering itself, independent of what this box has installed:
    # a root list whose FIRST entry lacks the file and whose SECOND has it must
    # resolve, not flag.
    second = tm.missing_dev_requirement(
        gtk, ["/nonexistent-a/", "/usr/include/gtk-2.0/gtk/"])
    check(second is None or not os.path.exists("/usr/include/gtk-2.0/gtk/gtk.h"),
          "a hit in the SECOND root satisfies it",
          "checking only the first root would have skipped this job")

    print("4. the -I rule is about the directory, not about a test name")
    bad = job("./$(COMPILER) -I/usr/include/pxx-absent-dir/ test/x.pas $(TESTTMP)/x")
    good = job("./$(COMPILER) -I/usr/include/ test/x.pas $(TESTTMP)/x")
    gb = tm.missing_dev_requirement(bad, roots)
    gg = tm.missing_dev_requirement(good, roots)
    check(gb and "pxx-absent-dir" in gb[0],
          "an -I naming a missing directory is flagged", str(gb))
    check(gg is None, "and one naming a present directory is not", str(gg))

    print("5. a job that RUNS under xvfb needs xvfb, which is a third profile")
    import shutil
    xv = job("xvfb-run -a $(TESTTMP)/test_c_gtk_window26")
    gx = tm.missing_dev_requirement(xv, roots)
    check((gx is not None) == (shutil.which("xvfb-run") is None),
          "flagged exactly when xvfb-run is absent from PATH",
          "xvfb-run present=%s, verdict=%s"
          % (bool(shutil.which("xvfb-run")), gx))

    print("6. the reason names the PACKAGE, which is the actionable half")
    check(tm._pkg_for("/usr/include/gtk-2.0/gtk/gtk.h") == "libgtk2.0-dev",
          "gtk-2.0 maps to libgtk2.0-dev")
    check(tm._pkg_for("/usr/include/gtk-3.0") == "libgtk-3-dev",
          "and gtk-3.0 to libgtk-3-dev — they are DIFFERENT packages",
          "one flag for both is how five jobs became eighteen tickets")
    # Driven through apply_host_lib_skips, not through the predicate, so the
    # STATUS transition is asserted too -- and via the -I rule, which fires on
    # every box regardless of what is installed. A row that can only run where
    # a package is missing would be a guard most machines never execute.
    j = job("./$(COMPILER) -I/usr/include/pxx-absent-dir/ test/x.pas $(TESTTMP)/x")
    tm.apply_host_lib_skips([j])
    check(j.status == "skip",
          "apply_host_lib_skips moves the job to SKIP, not to fail", j.status)
    check("cannot pass here" in (j.skip_reason or "")
          and "about the box rather than about the tree" in (j.skip_reason or ""),
          "and the reason says whose fault it is NOT",
          (j.skip_reason or "")[:70])
    # ...and it must not walk over a job that already has a reason: the first
    # reason is the actionable one, same rule as the emulator guard.
    k = job("./$(COMPILER) -I/usr/include/pxx-absent-dir/ test/x.pas $(TESTTMP)/x")
    k.status, k.skip_reason = "skip", "host capability absent: rdrand"
    tm.apply_host_lib_skips([k])
    check(k.skip_reason == "host capability absent: rdrand",
          "and it does not relabel an already-skipped job", k.skip_reason)

    # ---------------------------------------------------------------- 7
    # THE REAL POPULATION. Every row above is a synthetic job I wrote, and all
    # fourteen were green while the guard skipped 83 healthy jobs -- including
    # compiler/compiler.pas, the self-host job. A control drawn from the wrong
    # population passes and certifies the broken instrument; these are the
    # actual recipes, which is the only population the question was ever about.
    print("7. THE REAL POPULATION — the control the synthetic rows could not be")
    roots = tm.uses_fallback_roots()
    jobs, skipped = [], []
    for tgt in ("test-core", "lib-test", "demos"):
        for jb in tm.split_jobs(tgt, tm.make_dry_run(tgt)):
            jobs.append(jb)
            if tm.missing_dev_requirement(jb, roots):
                skipped.append((tm.extract_src(jb.lines) or "?").split()[0])
    check(len(jobs) > 1500,
          "the scan reached a real population, not an empty one", len(jobs))
    # THIS BOX HAS EVERY PACKAGE. Any skip here is therefore a FALSE one, and
    # it is silent -- so the assertion is zero, not "few". Three bugs died on
    # this row, fixed in sequence: 83 false skips -> 47 -> 2 -> 0.
    #   * a case-SENSITIVE unit lookup: `uses SysUtils`, lib/rtl/sysutils.pas
    #   * a hardcoded search path ignoring the job's own -Fu/-I -- the unit
    #     path is ON THE COMMAND LINE (`-Futest/chdrstatic`), not in a list
    #   * a `uses` regex reading English prose out of a header COMMENT: "Uses
    #     only the language surface that ALL backends support today" yielded
    #     the unit `i386` and would have skipped the conformance harness
    # Those are the CUMULATIVE counts in fix order, not a per-cause split --
    # reverting each one alone now gives 2, 45 and 1, because the three
    # overlap. Each still takes this row red on its own, which is what the
    # row has to be able to do; the decomposition is not something I measured
    # and is not claimed.
    check(not skipped,
          "no job on a fully-provisioned box is skipped for an absent library",
          "%d false skip(s): %s" % (len(skipped), " ".join(sorted(set(skipped))[:6])))
    # ...and the same real population with the roots taken away MUST fire, or
    # the zero above is just a guard that stopped working.
    fired = sorted({(tm.extract_src(jb.lines) or "?").split()[0] for jb in jobs
                    if tm.missing_dev_requirement(
                        jb, ["/nonexistent-a/", "/nonexistent-b/"])})
    check(len(fired) >= 4 and any("gtk" in f for f in fired),
          "and with the roots absent the real jobs DO fire",
          "%d: %s" % (len(fired), " ".join(f.split("/")[-1] for f in fired)))
    # A job whose -Fu the SHELL computes is not statically knowable, and an
    # unknown path is not an absent one. test-core's fgl rung builds
    # -Fu$fglsrc from whichever corpus tree exists and does its own absence
    # check; judging it skipped a green job on a healthy box.
    shell = tm.job_from_lines(["./$(COMPILER) --mimic-fpc -Fu$$fglsrc "
                               "test/test_fgl_use.pas $(TESTTMP)/o"]) \
        if hasattr(tm, "job_from_lines") else job(
            "./$(COMPILER) --mimic-fpc -Fu$$fglsrc test/test_fgl_use.pas o")
    check(tm._job_unit_dirs(shell) is None,
          "a shell-computed -Fu means DO NOT JUDGE, not \"path absent\"",
          tm._job_unit_dirs(shell))

    print("\n  %d guard(s), %d FAIL" % (18, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
