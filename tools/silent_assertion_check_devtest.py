#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: tools/silent_assertion_check.py must catch what it is for, and
must not catch what it is not.

The guard exists so that ~3900 conversions to `tools/expect_same.sh` cannot rot
back into bare `test` assertions. A guard with no positive control is not a
guard, so five of the cases below are inputs it MUST reject.

THE FOURTH IS THE ONE THAT MATTERS MOST, because it is a real defect this
scanner had. The first draft read PHYSICAL lines and reported ten offenders;
four of them carry their `|| { echo ...; exit 1; }` on the NEXT continued line
and were never silent. The scanner was answering a narrower question than the
shell asks — which is the exact failure this whole ticket family is about,
committed by the guard written to prevent it. `t_a_fail_branch_on_a_continued_
line_is_not_silent` is that bug, pinned.

And the negative cases are not padding either: a rule that fires on
`if ...; then assert; else echo skip; fi` would be noise on a legal shape (`fi`
yields the taken branch's last status), and a noisy guard gets switched off.

Run: tools/silent_assertion_check_devtest.py   (exit 0 = pass)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402
import silent_assertion_check as sac    # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
MAKEFILE = os.path.join(os.path.dirname(HERE), "Makefile")


def scan(body):
    return sac.scan("target:\n" + body + "\n")


def t_a_silent_output_comparison_is_caught():
    silent, _ = scan('\ttest "$$out" = "$$(printf \'a\\nb\')"')
    assert len(silent) == 1, "a bare silent assertion was not caught: %r" % (silent,)
    return "a bare `test <out> = <subst>` is rejected"


def t_a_vacuous_assertion_is_caught():
    _, vac = scan('\ttest "$$out" = "x"; test "$$rc" = "42"')
    assert len(vac) == 1, "an assertion whose status is discarded was not caught"
    return "`test A; test B` — A cannot fail — is rejected"


def t_a_vacuous_expect_same_is_caught():
    _, vac = scan('\ttools/expect_same.sh a "$$x" "1"; tools/expect_same.sh b "$$y" "2"')
    assert len(vac) == 1, "a discarded expect_same status was not caught"
    return "the helper is not exempt from the discarded-status rule"


def t_a_fail_branch_on_a_continued_line_is_not_silent():
    """The scanner's own bug, pinned: `||` arriving on the NEXT physical line."""
    silent, _ = scan(
        '\ttest "$$out" = "$$(printf \'x\')" \\\n'
        '\t  || { echo "lbl: FAIL - [$$out]"; exit 1; }')
    assert not silent, \
        "a fail branch on a continued line was read as silent: %r" % (silent,)
    return "continuations are joined before the line is judged"


def t_an_explained_assertion_on_one_line_is_not_silent():
    silent, _ = scan('\ttest "$$out" = "$$(printf \'x\')" || { echo bad; exit 1; }')
    assert not silent, "an explained assertion was flagged: %r" % (silent,)
    return "`|| { echo ...; exit 1; }` is accepted"


def t_two_literal_operands_are_not_flagged():
    """No command substitution: the reason names the wrong lines, but it does
    not fabricate a plausible finding. Out of scope on purpose."""
    silent, _ = scan('\ttest "$$rc" = "1"')
    assert not silent, "a literal comparison was flagged: %r" % (silent,)
    return "a literal-vs-literal comparison is out of scope"


def t_a_numeric_comparison_on_a_substitution_is_caught():
    """`-ge` was outside the first population and four `grep -c` count
    assertions sat silent behind it. The rule is "nothing prints when this
    fails", and test(1) prints nothing for -ge exactly as it does for =."""
    silent, _ = scan('\ttest "$$(grep -c marked $(LOG))" -ge 6')
    assert len(silent) == 1, \
        "a silent numeric comparison was not caught: %r" % (silent,)
    return "`test <subst> -ge N` with no fail branch is rejected"


def t_a_numeric_comparison_with_a_fail_branch_is_accepted():
    silent, _ = scan('\ttest "$$(grep -c marked $(LOG))" -ge 6 '
                     '|| { echo "count $$(grep -c marked $(LOG)), want >= 6"; exit 1; }')
    assert not silent, "an explained numeric comparison was flagged: %r" % (silent,)
    return "the same comparison that says why is accepted"


def t_an_if_then_else_is_not_vacuous():
    _, vac = scan('\t@if command -v qemu >/dev/null; then \\\n'
                  '\t  tools/expect_same.sh a "$$x" "1"; \\\n'
                  '\telse echo "SKIP"; \\\n'
                  '\tfi')
    assert not vac, "a then/else assertion was called vacuous: %r" % (vac,)
    return "`then assert; else echo; fi` is legal and is not flagged"


def t_expect_same_suppresses_the_silent_rule():
    silent, _ = scan('\ttools/expect_same.sh lbl "$$($(X))" "$$(printf \'a\')"')
    assert not silent, "the helper itself was flagged as silent: %r" % (silent,)
    return "a converted line is accepted"


def t_a_comment_is_not_scanned():
    silent, vac = scan('\t@# test "$$out" = "$$(printf \'a\')"; test "$$rc" = "1"')
    assert not silent and not vac, "a comment was scanned: %r %r" % (silent, vac)
    return "a recipe comment is not an assertion"


def t_the_real_makefile_is_clean():
    """The regression half: this is what makes the conversion a property of the
    file rather than a one-time cleanup."""
    with open(MAKEFILE) as fh:
        silent, vac = sac.scan(fh.read())
    assert not silent and not vac, \
        "Makefile has %d silent and %d vacuous assertion(s); first: %s" % (
            len(silent), len(vac),
            (silent + vac)[0][1][:120] if (silent or vac) else "")
    return "the repo's own Makefile is clean"


TESTS = [t_a_silent_output_comparison_is_caught,
         t_a_vacuous_assertion_is_caught,
         t_a_vacuous_expect_same_is_caught,
         t_a_fail_branch_on_a_continued_line_is_not_silent,
         t_an_explained_assertion_on_one_line_is_not_silent,
         t_two_literal_operands_are_not_flagged,
         t_a_numeric_comparison_on_a_substitution_is_caught,
         t_a_numeric_comparison_with_a_fail_branch_is_accepted,
         t_an_if_then_else_is_not_vacuous,
         t_expect_same_suppresses_the_silent_rule,
         t_a_comment_is_not_scanned,
         t_the_real_makefile_is_clean]


def main():
    rc = 0
    print("silent-assertion devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("silent-assertion OK" if rc == 0 else "silent-assertion BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
