#!/usr/bin/env python3
"""Guards for tools/devtest_case_registration.py.

The controls that matter here are the two the checker itself was built to make
possible: a case that IS registered must pass, and a case that is NOT must be
rejected -- and the rejecting control is built by DELETING one entry from a real
harness in the tree, not from a synthetic fixture. A synthetic fixture would
test the shape I imagined; the repo's harnesses are the population the question
is about, and it was a wrong assumption about that population (that every
harness spells its list `TESTS =` at module level) that made the first draft of
this checker report three false positives.
"""

import ast
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import devtest_case_registration as dcr
from devtest_report import fail_detail

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")

# One harness of each spelling, so a change that only understands one is caught.
MODULE_LEVEL_LIST = os.path.join(TOOLS, "silent_assertion_check_devtest.py")
INLINE_TUPLE_LIST = os.path.join(TOOLS, "twatch_full_commit_devtest.py")


def _unlisted(text):
    tree = ast.parse(text)
    defs = dcr._case_defs(tree)
    ref = dcr._referenced(tree)
    if dcr._self_discovering(tree, ref):
        return []
    return [d for d in defs if d not in ref]


def _drop_one_registration(path):
    """Remove exactly one case from a real harness's run list.

    Finds a `t_*` that the file both DEFINES and REFERENCES, then deletes the
    referencing line. Asserts the edit applied and that it removed a reference
    rather than a definition -- an edit that silently did nothing would make
    this control pass for the same reason the defect it is controlling for
    passes, which is the failure this whole checker exists to prevent.
    """
    text = open(path, encoding="utf-8").read()
    tree = ast.parse(text)
    defs = dcr._case_defs(tree)
    assert defs, "%s defines no cases; wrong file for this control" % path
    ref = dcr._referenced(tree)
    victim = next((d for d in defs if d in ref), None)
    assert victim, "%s registers none of its cases; wrong file" % path

    out = []
    dropped = 0
    for line in text.split("\n"):
        stripped = line.strip()
        if (dropped == 0 and victim in stripped and not stripped.startswith("def ")
                and not stripped.startswith("#")):
            dropped += 1
            continue
        out.append(line)
    assert dropped == 1, "the control edit removed %d lines, expected 1" % dropped
    hacked = "\n".join(out)
    assert hacked != text, "the control edit changed nothing"
    # the definition must survive -- we removed a REGISTRATION, not a case
    assert victim in dcr._case_defs(ast.parse(hacked)), \
        "the control removed the definition, not the registration"
    return victim, hacked


def t_the_repo_is_clean_right_now():
    """Every harness in the tree registers every case it defines."""
    rc = dcr.main(["devtest_case_registration"])
    assert rc == 0, "the repo has an unregistered devtest case; run the checker"


def t_an_unregistered_case_is_caught_module_level_list():
    """The `TESTS = (...)` spelling, controlled by deleting one entry."""
    victim, hacked = _drop_one_registration(MODULE_LEVEL_LIST)
    missing = _unlisted(hacked)
    assert missing == [victim], \
        "expected exactly [%s] unlisted, got %r" % (victim, missing)


def t_an_unregistered_case_is_caught_inline_tuple():
    """The inline-tuple-in-main() spelling -- the one the first draft missed."""
    victim, hacked = _drop_one_registration(INLINE_TUPLE_LIST)
    missing = _unlisted(hacked)
    assert missing == [victim], \
        "expected exactly [%s] unlisted, got %r" % (victim, missing)


def t_the_unhacked_harnesses_are_the_negative_control():
    """The same two files, untouched, must report nothing.

    Without this the positive controls above prove only that the checker says
    something; they do not prove it says it because of the edit.
    """
    for path in (MODULE_LEVEL_LIST, INLINE_TUPLE_LIST):
        missing = _unlisted(open(path, encoding="utf-8").read())
        assert missing == [], "%s reports %r before any edit" % (path, missing)


def t_a_self_discovering_harness_is_exempt():
    """A harness that names no case and reads globals() cannot drift."""
    src = ("def t_one():\n    pass\n\n"
           "def main():\n"
           "    for k in globals():\n        pass\n")
    assert _unlisted(src) == [], "a globals()-discovering harness must be exempt"


def t_a_case_referenced_only_as_a_string_counts():
    """A string in the run list is a registration."""
    src = ("def t_one():\n    pass\n\nTESTS = ['t_one']\n")
    assert _unlisted(src) == [], "a string reference is a registration"


def t_a_file_defining_no_cases_is_not_counted():
    """It cannot be a finding, and counting it would inflate the denominator."""
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix="_devtest.py", delete=False) as fh:
        fh.write("def helper():\n    pass\n")
        p = fh.name
    n, missing, disc = dcr.audit(p)
    assert n == 0 and missing == [], "a caseless file must audit as empty, got %r" % (missing,)


def t_an_empty_population_is_not_a_pass():
    """A clean result over nothing is the null result this repo distrusts."""
    rc = dcr.main(["devtest_case_registration", os.path.join(TOOLS, "devtest_report.py")])
    assert rc == 1, "a run whose population contains no harness must refuse, not pass"


TESTS = (
    t_the_repo_is_clean_right_now,
    t_an_unregistered_case_is_caught_module_level_list,
    t_an_unregistered_case_is_caught_inline_tuple,
    t_the_unhacked_harnesses_are_the_negative_control,
    t_a_self_discovering_harness_is_exempt,
    t_a_case_referenced_only_as_a_string_counts,
    t_a_file_defining_no_cases_is_not_counted,
    t_an_empty_population_is_not_a_pass,
)


def main():
    print("devtest-case-registration devtest (%d guards)" % len(TESTS))
    listed = sorted(f.__name__ for f in TESTS)
    defined = sorted(k for k in list(globals())
                     if k.startswith("t_") and callable(globals()[k]))
    unlisted = [n for n in defined if n not in listed]
    if unlisted:
        # This harness is the one place where shipping the very defect it polices
        # would be silent AND ironic. Same guard it exists to install elsewhere.
        print("  %d case(s) defined but NOT in TESTS: %s" % (len(unlisted), ", ".join(unlisted)))
        return 1

    bad = 0
    for fn in TESTS:
        try:
            fn()
        except Exception as exc:          # noqa: BLE001 -- a devtest reports, it does not raise
            print("  FAIL %s: %s" % (fn.__name__, fail_detail(exc)))
            bad += 1
        else:
            doc = (fn.__doc__ or "").strip().split("\n")[0]
            print("  ok   %s — %s" % (fn.__name__, doc))
    if bad:
        print("devtest-case-registration devtest: %d FAILED" % bad)
        return 1
    print("devtest-case-registration devtest OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
