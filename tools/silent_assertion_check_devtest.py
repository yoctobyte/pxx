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
REPO = os.path.dirname(HERE)
MAKEFILE = os.path.join(REPO, "Makefile")


def scan(body):
    """The first two rules only -- most cases below predate STALE-PIN."""
    silent, vac, _ = sac.scan("target:\n" + body + "\n")
    return silent, vac


def scan_pins(body):
    """STALE-PIN reads files from the CWD, as gate.sh does at the repo root.

    The first draft of these cases passed an ABSOLUTE fixture path, which the
    scanner's own path regex cannot match (it anchors on `test/`, `lib/` or
    `examples/`), so nothing was named, nothing was compared, and THREE of the
    four negative cases passed without the rule ever running. Two positive
    cases failing is what exposed it -- which is the argument for having them.
    """
    cwd = os.getcwd()
    os.chdir(REPO)
    try:
        _, _, stale = sac.scan("target:\n" + body + "\n")
    finally:
        os.chdir(cwd)
    return stale


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


def t_a_vacuous_runtime_assertion_is_caught():
    _, vac = scan('\ttools/assert_no_leak.sh a 200 $(T)/x; tools/expect_same.sh b "$$y" "2"')
    assert len(vac) == 1, "a discarded assert_no_leak status was not caught"
    return "assert_no_leak.sh is an assertion for the discarded-status rule"


def t_a_vacuous_alloc_ceiling_is_caught():
    _, vac = scan('\ttools/assert_alloc_ceiling.sh a 50 $(T)/x; test "$$rc" = "0"')
    assert len(vac) == 1, "a discarded assert_alloc_ceiling status was not caught"
    return "assert_alloc_ceiling.sh is too -- 104 recipe lines use these two"


def t_a_runtime_assertion_joined_with_and_is_accepted():
    _, vac = scan('\ttools/assert_no_leak.sh a 200 $(T)/x && tools/expect_same.sh b "$$y" "2"')
    assert not vac, "`&&` preserves the first status and must not be flagged"
    return "the rule is about `;`, not about the tool"


def t_a_runtime_assertion_does_not_become_silent():
    sil, _ = scan('\ttools/assert_no_leak.sh a 200 $(T)/x')
    assert not sil, "widening ASSERT must not leak into the SILENT rule"
    return "SILENT reads CMP, not ASSERT -- these tools always print"


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
        silent, vac, stale = sac.scan(fh.read())
    assert not silent and not vac and not stale, \
        "Makefile has %d silent, %d vacuous and %d stale-pin assertion(s); first: %s" % (
            len(silent), len(vac), len(stale),
            (silent + vac + [(s[0], s[1]) for s in stale])[0][1][:120]
            if (silent or vac or stale) else "")
    return "the repo's own Makefile is clean"


# --- STALE-PIN -------------------------------------------------------------
# The rule's founding case, kept as data rather than as prose: a NINE-line
# fixture whose row pinned `pascal26:10:`. Both halves landed in one commit and
# the row passed for eight hours, because the compiler was reporting the wrong
# line too and the two wrong numbers agreed.

# REPO-RELATIVE on purpose -- see scan_pins. It is also the real fixture and
# not a synthetic one, so if it ever grows past nine lines these cases go red
# and say so, rather than silently testing a different question.
NINE_LINE_FIXTURE = ("test/test_nilpy_a_referenced_symbol_from_a_library"
                     "_that_cannot_exist.npy")


def t_a_pin_past_the_end_of_the_file_is_caught():
    stale = scan_pins(
        '\t@out=$$(./$(COMPILER) %s $(T)/x 2>&1); \\\n'
        '\t  test "$$rc" = "1" \\\n'
        '\t  && printf \'%%s\\n\' "$$out" | grep -q \'^pascal26:10: error: x\''
        % NINE_LINE_FIXTURE)
    assert len(stale) == 1, \
        "a pin past the end of a nine-line fixture was not caught: %r" % (stale,)
    return "`pascal26:10:` against a 9-line file is rejected"


def _row(pin, extra=""):
    return ('\t@out=$$(./$(COMPILER) %s $(T)/x 2>&1); \\\n'
            '\t  && printf \'%%s\\n\' "$$out" | grep -q \'^pascal26:%d: error: x\'%s'
            % (NINE_LINE_FIXTURE, pin, extra))


def t_a_pin_inside_the_file_is_accepted():
    """The rule must not fire on the ordinary case, or it is noise and gets
    switched off. Line 9 of a 9-line file is legal and is the boundary.

    AND THE TWIN IS THE POINT: the identical row one line further on MUST fire.
    Without it this case passes whenever the rule fails to run at all, which is
    precisely how it passed while the fixture path was unmatchable."""
    assert not scan_pins(_row(9)), "a legal in-range pin was flagged"
    assert scan_pins(_row(10)), \
        "the same row at line 10 did not fire -- the rule never ran, so the " \
        "in-range case above proves nothing"
    return "line 9 of a 9-line file is in range; line 10 is not"


def t_the_line_count_is_not_off_by_one():
    """THE BUG THE POSITIVE CONTROL CAUGHT, PINNED. The first draft counted
    lines as `content.count(chr(10)) + 1`, which is right only for a file with
    no trailing newline. The nine-line fixture measured 10, the pin was 10,
    `10 > 10` is False -- so the rule looked straight at the defect it was
    written from and reported the file clean. This case is the reason the
    positive control above can fail."""
    n = sac._line_count(NINE_LINE_FIXTURE)
    assert n == 9, ("the nine-line fixture measured %r lines; a +1 on a "
                    "newline-terminated file disarms the whole rule" % (n,))
    return "a newline-terminated 9-line file counts as 9, not 10"


def t_a_row_asserting_an_in_line_is_not_flagged():
    """A diagnostic that names another file indexes THAT file. Three such rows
    are live (the incdiag family) and all are correct."""
    stale = scan_pins(
        '\t@out=$$(./$(COMPILER) %s $(T)/x 2>&1); \\\n'
        '\t  echo "$$out" | grep -q \'^pascal26:63: error:\' \\\n'
        '\t  && echo "$$out" | grep -q \'^  in: .*badinc\\.inc$$\''
        % NINE_LINE_FIXTURE)
    assert not stale, "a row asserting an `in:` line was flagged: %r" % (stale,)
    assert scan_pins(_row(63)), \
        "the same pin without the `in:` assertion did not fire -- the rule " \
        "never ran, so the acceptance above proves nothing"
    return "asserting `in:` says the pin indexes another file"


def t_the_marker_suppresses_the_rule():
    """For the rows that pipe through `head -1` and so have no `in:` line to
    assert. One live row needs it."""
    stale = scan_pins(
        '\t@# PIN NAMES ANOTHER FILE -- line 18 is in the used unit.\n'
        '\t@tools/expect_same.sh lbl "$$(./$(COMPILER) %s $(T)/x 2>&1 | head -1)" \\\n'
        '\t  "pascal26:18: error: x"' % NINE_LINE_FIXTURE)
    assert not stale, "the opt-out marker did not suppress the rule: %r" % (stale,)
    assert scan_pins(
        '\t@tools/expect_same.sh lbl "$$(./$(COMPILER) %s $(T)/x 2>&1 | head -1)" \\\n'
        '\t  "pascal26:18: error: x"' % NINE_LINE_FIXTURE), \
        "the same row without the marker did not fire -- the rule never ran"
    return "PIN NAMES ANOTHER FILE in the comment block above opts out"


def t_the_marker_only_covers_the_row_below_it():
    """The marker must not be a file-wide switch: a second row further down
    with its own stale pin still fires. Same shape as the repo's other
    per-instance markers."""
    stale = scan_pins(
        '\t@# PIN NAMES ANOTHER FILE -- line 18 is in the used unit.\n'
        '\t@tools/expect_same.sh a "$$(./$(COMPILER) %s $(T)/x 2>&1 | head -1)" \\\n'
        '\t  "pascal26:18: error: x"\n'
        '\t@tools/expect_same.sh b "$$(./$(COMPILER) %s $(T)/y 2>&1 | head -1)" \\\n'
        '\t  "pascal26:40: error: x"' % (NINE_LINE_FIXTURE, NINE_LINE_FIXTURE))
    assert len(stale) == 1, \
        "the marker leaked past its own row: %r" % (stale,)
    return "the marker covers one row, not the rest of the file"


def t_a_row_naming_no_source_file_is_skipped():
    """A row asserting against a LOG has no line count to compare with. Silence
    here is a deliberate absence of evidence, not a pass."""
    stale = scan_pins('\t@grep -q "pascal26:3: error: requested failure" $(T)/foo.log')
    assert not stale, "a row naming no source file was flagged: %r" % (stale,)
    return "no named source means no comparison, so no verdict"


# EVERY t_* below must appear in this list -- a case defined and not listed is a
# guard that silently does not run. Four were added 2026-09-05 and the tell was
# the printed count not moving; main() now asserts the list against the module.
TESTS = [t_a_silent_output_comparison_is_caught,
         t_a_vacuous_assertion_is_caught,
         t_a_vacuous_expect_same_is_caught,
         t_a_vacuous_runtime_assertion_is_caught,
         t_a_vacuous_alloc_ceiling_is_caught,
         t_a_runtime_assertion_joined_with_and_is_accepted,
         t_a_runtime_assertion_does_not_become_silent,
         t_a_fail_branch_on_a_continued_line_is_not_silent,
         t_an_explained_assertion_on_one_line_is_not_silent,
         t_two_literal_operands_are_not_flagged,
         t_a_numeric_comparison_on_a_substitution_is_caught,
         t_a_numeric_comparison_with_a_fail_branch_is_accepted,
         t_an_if_then_else_is_not_vacuous,
         t_expect_same_suppresses_the_silent_rule,
         t_a_comment_is_not_scanned,
         t_the_real_makefile_is_clean,
         t_a_pin_past_the_end_of_the_file_is_caught,
         t_a_pin_inside_the_file_is_accepted,
         t_the_line_count_is_not_off_by_one,
         t_a_row_asserting_an_in_line_is_not_flagged,
         t_the_marker_suppresses_the_rule,
         t_the_marker_only_covers_the_row_below_it,
         t_a_row_naming_no_source_file_is_skipped]


def main():
    # A case defined and left out of TESTS reads exactly like a passing suite.
    defined = sorted(k for k in globals() if k.startswith("t_") and callable(globals()[k]))
    listed = sorted(f.__name__ for f in TESTS)
    missing = [n for n in defined if n not in listed]
    if missing:
        print("silent-assertion devtest: %d case(s) defined but NOT in TESTS: %s"
              % (len(missing), ", ".join(missing)))
        return 1
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
