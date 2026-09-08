#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the untested population is not the could-have-caused population.

`needs_test` asks *is this commit outside devdocs/ and docs/* — a question
about which commits a gate was never run on. A bisect needs a different
question: *could this commit have changed what the failing job does?* The two
differ exactly where a commit touches a file that is neither documentation nor
an input to that job.

Measured 2026-09-08, regression-test-emit-obj-c-obj-data-dup-a: ten commits in
the range, ZERO touching compiler/, lib/ or tools/, and the only two in the
`needs_test` population touching one file — test/pascal-conformance/pxx.skip, a
Pascal conformance skip list a C object-emission job does not read. So
`no_testable_change` did not fire (two is not zero) and the idle bisect was
queued to converge on a skip-list edit and name it for an `--emit-obj` failure.
Two of the ten commits were prose docs written by the coordinator, which is the
sharpest form of the argument available: a seat that could not have caused the
defect was inside its blame population.

THE POSITIVE CONTROL IS THE POINT OF THIS FILE. A guard that declines to
bisect and cannot be made to bisect is the failure mode this repo names most
often, and it would be invisible in production because almost every range is
the ordinary kind — one compiler commit and a verdict. So the control is drawn
from that population and asserted: a range containing a compiler/ commit MUST
still bisect.

Run: tools/twatch_range_causality_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402,F401

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

FAILS = []


def check(name, cond, detail=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  RED  %s" % name)
        FAILS.append("%s\n      %s" % (name, detail))


def git(repo, *a):
    return subprocess.run(("git",) + a, cwd=repo, capture_output=True,
                          text=True, check=True).stdout.strip()


class FakeClone(object):
    """Just the two members range_non_causal() touches."""

    def __init__(self, path):
        self.path = path

    def commits_between(self, good, bad):
        out = git(self.path, "rev-list", "--reverse", "%s..%s" % (good, bad))
        return out.splitlines() if out else []


def build_repo():
    d = tempfile.mkdtemp(prefix="rangecausal-devtest-")
    git(d, "init", "-q", "-b", "main")
    git(d, "config", "user.email", "t@example.invalid")
    git(d, "config", "user.name", "t")

    def commit(path, text, msg):
        full = os.path.join(d, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "a").write(text + "\n")
        git(d, "add", "-A")
        git(d, "commit", "-q", "-m", msg)
        return git(d, "rev-parse", "HEAD")

    shas = {}
    # A root commit has no parent; keep it out of every range under test.
    shas["root"] = commit("compiler/compiler.pas", "unit root;", "root")
    shas["good"] = commit("compiler/compiler.pas", "{ good }", "a real change")
    shas["docs"] = commit("devdocs/dev/playbook.md", "prose", "docs(playbook)")
    shas["skip1"] = commit("test/pascal-conformance/pxx.skip",
                           "tgeneric16  reason", "docs(skip): a reason")
    shas["skip2"] = commit("test/pascal-conformance/pxx.skip",
                           "tgeneric17  reason", "docs(tickets): another")
    shas["bad"] = commit("devdocs/progress/tstate/seven.json", "{}",
                         "tstate(seven): GREEN")
    shas["code"] = commit("compiler/ir_codegen.inc", "{ real }",
                          "fix(A): a real compiler change")
    shas["newtest"] = commit("test/c_obj_data_dup_a.c", "int x;",
                             "test(C): a new source")
    return d, shas


EMIT = "test-emit-obj#src:test/c_obj_data_dup_a.c"
CONF = "test-pascal-conformance#src:test/pascal-conformance/tgeneric16.pas"


def main():
    d, sh = build_repo()
    clone = FakeClone(d)

    def reg(good, bad, job=EMIT):
        return {"good": sh[good], "bad": sh[bad], "job": job}

    print("twatch range-causality devtest")

    # --- the live case ---
    check("a range of only docs and conformance-skip edits is NON-causal",
          tw.range_non_causal(clone, reg("good", "bad")),
          "the reproduced shape did not classify; the bisect would still run")

    # --- THE POSITIVE CONTROL, drawn from the ordinary population ---
    check("POSITIVE CONTROL: a range containing a compiler/ commit still bisects",
          not tw.range_non_causal(clone, reg("good", "code")),
          "a real compiler change was called non-causal — this guard can now "
          "suppress a genuine bisect, which is worse than the defect it fixes")

    # --- the manifest is causal for its OWN family ---
    check("the same skip edits ARE causal for a pascal-conformance job",
          not tw.range_non_causal(clone, reg("good", "bad", CONF)),
          "pxx.skip steers that corpus; excluding it there is a real blind spot")

    # --- fails open on anything not in the table ---
    check("a test source not in the manifest table is causal",
          not tw.range_non_causal(clone, reg("bad", "newtest")),
          "an unknown test/ file was excluded; the allowlist must fail open")
    check("a single commit touching compiler/ is causal",
          tw.commit_could_affect(d, sh["code"], EMIT))
    check("a docs-only commit is not",
          not tw.commit_could_affect(d, sh["docs"], EMIT))

    # --- never suppress on missing data ---
    check("no bounds means NOT non-causal",
          not tw.range_non_causal(clone, {"job": EMIT}),
          "a regression with no recorded range was suppressed")
    check("an EMPTY range is not this rule's claim",
          not tw.range_non_causal(clone, reg("bad", "bad")),
          "an empty range belongs to no_testable_change, not here — claiming "
          "it twice makes the two indistinguishable in the ticket")

    # --- the deliberate overlap, asserted so it is not discovered as a bug ---
    check("a docs-only range satisfies BOTH rules, deliberately",
          tw.range_non_causal(clone, reg("good", "docs")),
          "the empty-testable case is a subset of this one; both may fire")

    print("twatch range-causality OK" if not FAILS else "twatch range-causality BROKEN")
    for f in FAILS:
        print("  " + f)
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
