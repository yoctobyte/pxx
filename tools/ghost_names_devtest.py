#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: ghost_names must find the renamed routine and nothing else.

The tool's whole value is its POPULATION, so every case here is about what it
must NOT report. Three naive versions of this check exist and all of them flag
several hundred names in the real tree, which is as empty as a check that never
fires. The discriminators under test:

  * once DEFINED as a routine in compiler/ history -- a prose word is not a ghost
  * absent from ALL tracked Pascal code today -- an RTL name a compiler comment
    mentions is live code somewhere
  * still cited in a compiler/ COMMENT -- and the comment matcher must not eat
    code, which is the regression case below

THE REGRESSION CASE IS THE IMPORTANT ONE. The first version matched
`(* ... *)` as a comment form under re.S. This tree does not use it, but `(*`
appears constantly INSIDE `{ }` comments as C pointer syntax (`(*pfrom = sp)`),
so the lazy match ran from one comment's `(*` to some later `*)` and swallowed
the code between. 18 hits became 88, and the extra 70 were function definitions
reported as comments -- a comment matcher that matched code, inside the tool
whose job is to tell comments from code. That case must stay.

Run: tools/ghost_names_devtest.py   (exit 0 = pass)
"""
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402,F401

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "ghost_names.py")

FAILS = []


def check(name, cond, detail):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  RED  %s" % name)
        FAILS.append("%s\n      %s" % (name, detail))


def git(repo, *a):
    return subprocess.run(("git", "-C", repo) + a, capture_output=True, text=True)


def build_repo():
    d = tempfile.mkdtemp(prefix="ghostnames-devtest-")
    os.makedirs(os.path.join(d, "compiler"))
    os.makedirs(os.path.join(d, "lib"))
    git(d, "init", "-q", "-b", "master")
    git(d, "config", "user.email", "t@example.invalid")
    git(d, "config", "user.name", "t")

    # Commit 1: two routines exist, both cited in comments.
    with open(os.path.join(d, "compiler", "a.inc"), "w") as f:
        f.write("function OldWalker(n: Integer): Integer;\n"
                "begin OldWalker := n; end;\n"
                "function GoneWalker(n: Integer): Integer;\n"
                "begin GoneWalker := n; end;\n"
                "function KeptWalker(n: Integer): Integer;\n"
                "begin KeptWalker := n; end;\n")
    with open(os.path.join(d, "lib", "rtl.pas"), "w") as f:
        f.write("function AnsiCompareText(a, b: string): Integer;\n"
                "begin AnsiCompareText := 0; end;\n")
    git(d, "add", "-A")
    git(d, "commit", "-q", "-m", "both walkers exist")

    # Commit 2: OldWalker is deleted; the comment that cites it stays, and so do
    # the three controls.
    with open(os.path.join(d, "compiler", "a.inc"), "w") as f:
        # Every hazard that broke a previous version is in this one comment and
        # the line after it. If any of them is mishandled the scanner hands back
        # code as prose, and `NotAComment` — a DEFINITION — gets reported.
        f.write(
            "{ This walk replaced OldWalker, which answered a different\n"
            "  question. KeptWalker is still the one to call, and\n"
            "  AnsiCompareText in the RTL is unrelated. A ProseNounPhrase\n"
            "  is not a routine.\n"
            "  A NESTED BRACE PAIR: g(**{\"a\":1,\"b\":2}) supplies zero\n"
            "  positional arguments, and this sentence is still inside the\n"
            "  comment — a non-nesting scanner ends it at the brace above.\n"
            "  AN UNMATCHED PAREN-STAR IN PROSE: `C(*xs)` and `def g(**kw)`\n"
            "  must not open anything. }\n"
            "function KeptWalker(n: Integer): Integer;\n"
            "begin\n"
            "  Error('(**mapping) is not supported; use a literal');\n"
            "  KeptWalker := n;\n"
            "end;\n"
            "function NotAComment(n: Integer): Integer;\n"
            "begin NotAComment := n; end;\n"
            "(* A real paren-star comment, the form pyparser.inc uses.\n"
            "   It cites GoneWalker, which is also a ghost. *)\n")
    git(d, "add", "-A")
    git(d, "commit", "-q", "-m", "delete OldWalker, keep the comment")
    return d


def run(repo, *args):
    r = subprocess.run([sys.executable, TOOL] + list(args), cwd=repo,
                       capture_output=True, text=True, timeout=120)
    return r.returncode, r.stdout + r.stderr


def t_a_deleted_routine_still_cited_in_a_comment_is_reported(repo):
    """MUST FIRE — this is the whole tool."""
    rc, out = run(repo)
    check("a deleted routine cited in a comment is reported",
          "OldWalker" in out,
          "the founding case was missed; output:\n%s" % out)


def t_a_routine_that_still_exists_is_not_reported(repo):
    rc, out = run(repo)
    check("a live routine is not reported", "KeptWalker" not in out,
          "a routine that still exists was called a ghost:\n%s" % out)


def t_a_prose_noun_phrase_is_not_reported(repo):
    """A CamelCase word that was never a routine is the 588-hit failure."""
    rc, out = run(repo)
    check("a CamelCase prose word is not reported",
          "ProseNounPhrase" not in out,
          "a word that was never a routine was reported:\n%s" % out)


def t_a_name_live_elsewhere_in_the_repo_is_not_reported(repo):
    """An RTL name a compiler comment mentions is live code somewhere."""
    rc, out = run(repo)
    check("a name defined outside compiler/ is not reported",
          "AnsiCompareText" not in out,
          "a name live in lib/ was reported as a ghost:\n%s" % out)


def t_pointer_syntax_in_a_comment_does_not_swallow_code(repo):
    """REGRESSION, three hazards at once — each broke a previous version.

    A `(*` in PROSE inside a brace comment; a `(*` inside a STRING LITERAL; and
    a nested brace pair that a non-nesting scanner closes early. All three end
    the same way: a function DEFINITION is scanned as comment text, so asserting
    that `NotAComment` is absent catches every one of them.
    """
    rc, out = run(repo)
    check("`(*` in prose, `(*` in a string, and a nested brace do not eat code",
          "NotAComment" not in out,
          "a function DEFINITION was scanned as comment text:\n%s" % out)


def t_a_paren_star_comment_is_still_scanned(repo):
    """The opposite failure: dropping `(* *)` silences the tool on nine real
    comments in pyparser.inc. A quiet instrument is not a clean one."""
    rc, out = run(repo)
    check("a `(* *)` comment is still read for citations",
          "GoneWalker" in out,
          "the paren-star comment form was not scanned at all:\n%s" % out)


def t_strict_exits_nonzero_and_the_default_does_not(repo):
    rc_plain, _ = run(repo)
    rc_strict, _ = run(repo, "--strict")
    check("the default exits 0 (it is a report, not a gate)", rc_plain == 0,
          "rc=%d — a permanently-red row is not a gate" % rc_plain)
    check("--strict exits 1 when ghosts are found", rc_strict == 1,
          "rc=%d — a caller that has cleaned the tree cannot keep it clean" % rc_strict)


def main():
    print("ghost_names: the population is the whole design")
    repo = build_repo()
    for case in (t_a_deleted_routine_still_cited_in_a_comment_is_reported,
                 t_a_routine_that_still_exists_is_not_reported,
                 t_a_prose_noun_phrase_is_not_reported,
                 t_a_name_live_elsewhere_in_the_repo_is_not_reported,
                 t_pointer_syntax_in_a_comment_does_not_swallow_code,
                 t_a_paren_star_comment_is_still_scanned,
                 t_strict_exits_nonzero_and_the_default_does_not):
        case(repo)
    if FAILS:
        print("\n%d FAIL:" % len(FAILS))
        for f in FAILS:
            print("  - %s" % f)
        return 1
    print("\nall guards pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
