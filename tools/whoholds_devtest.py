#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: whoholds must not report a topic quiet because it was aimed wrong.

Two defects are under test here and they are the same animal — an instrument
that answers, plausibly, about something else.

1. THE SESSION FALLBACK WAS DEAD AGAINST THE ONLY SPELLING THE SPEC PRODUCES.
   CLAUDE.md's trailer is a URL (`Claude-Session: https://claude.ai/code/
   session_01Bk...`), so the whitespace-delimited token starts with `https://`
   and the old `tok.startswith("session_")` test matched nothing, ever.
   Measured 2026-09-06: 722 commits in twelve hours, 509 with a URL-form
   trailer, 0 with a bare token. The tool printed `?×27` for a file whose every
   recent commit named its session, and told the caller they could not tell who
   to ask. After the fix the same query names five sessions.

2. `--containing=` EXISTS BECAUSE A FILENAME IS A CLAIM AND `git grep -l` IS A
   MEASUREMENT. A check aimed at a file that does not hold the code can only
   come back clear; it has no failure mode. So the mode that resolves files from
   a string the code owns must be LOUD when the string resolves to nothing —
   printing that as `quiet` would rebuild the defect one layer up.

Both guards are must-FIRE guards: each drives a case whose correct answer is
DIFFERENT FROM THE BROKEN ANSWER, because for both defects the broken answer is
the plausible one ("nobody is there") rather than an error.

Run: tools/whoholds_devtest.py   (exit 0 = pass)
"""
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402,F401

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "whoholds.py")

URL_TRAILER = ("Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n"
               "Claude-Session: https://claude.ai/code/session_01AbCdEfGhIjKlMn")
BARE_TRAILER = "Claude-Session: session_01ZyXwVuTsRq"

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
    """A repo with an origin/master and three commits touching one file.

    whoholds reads `origin/master` by name, so the ref is created explicitly —
    a test repo without it would make every row empty and every guard pass.
    """
    d = tempfile.mkdtemp(prefix="whoholds-devtest-")
    git(d, "init", "-q", "-b", "master")
    git(d, "config", "user.email", "t@example.invalid")
    git(d, "config", "user.name", "t")
    src = os.path.join(d, "thing.inc")
    with open(src, "w") as f:
        f.write("{ the door }\nnot a record member: expected a field\n")
    git(d, "add", "-A")
    git(d, "commit", "-q", "-m", "first: the URL spelling\n\n" + URL_TRAILER)
    with open(src, "a") as f:
        f.write("second line\n")
    git(d, "add", "-A")
    git(d, "commit", "-q", "-m", "second: the bare spelling\n\n" + BARE_TRAILER)
    with open(src, "a") as f:
        f.write("third line\n")
    git(d, "add", "-A")
    git(d, "commit", "-q", "-m", "third: a Lane line\n\nLane: frankQ\n" + URL_TRAILER)
    # A file the string does NOT appear in, so a resolver that returns the whole
    # tree is distinguishable from one that returns the right file.
    other = os.path.join(d, "unrelated.inc")
    with open(other, "w") as f:
        f.write("nothing to see\n")
    git(d, "add", "-A")
    git(d, "commit", "-q", "-m", "fourth: an untrailered commit elsewhere")
    git(d, "update-ref", "refs/remotes/origin/master", "HEAD")
    return d


def run(repo, *args):
    r = subprocess.run([sys.executable, TOOL] + list(args), cwd=repo,
                       capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout + r.stderr


def t_a_url_form_trailer_is_seen(repo):
    """MUST FIRE: this is defect 1. Before the fix the id was invisible."""
    rc, out = run(repo, "thing.inc", "--window=600")
    check("URL-form Claude-Session resolves to an id",
          "01AbCdEf" in out,
          "the spec's own spelling was not recognised; output:\n%s" % out)
    # THE ABLATION CAUGHT THIS GUARD BEING TOO WEAK TO FIRE. It first asserted
    # `?×3 not in out`, and the mutated tool prints `?×1` — every trailered
    # commit read as unidentified and the guard stayed green, because the count
    # it named was not the count the defect produces. Every commit in this
    # fixture identifies itself, so the correct assertion is that NO row is
    # unidentified at all.
    check("no trailered commit is counted as unidentified",
          "?×" not in out and "0+?" not in out,
          "a commit carrying a trailer read as '?'; output:\n%s" % out)


def t_a_bare_session_token_still_resolves(repo):
    """The old spelling must keep working — the fix widens, it does not move."""
    rc, out = run(repo, "thing.inc", "--window=600")
    check("bare session_ token still resolves",
          "01ZyXwVu" in out,
          "widening the match dropped the original form; output:\n%s" % out)


def t_a_lane_line_outranks_the_session_id(repo):
    rc, out = run(repo, "thing.inc", "--window=600")
    check("Lane: wins over the session id",
          "frankQ" in out,
          "the addressable field lost to the transcript id; output:\n%s" % out)


def t_a_string_nothing_owns_is_loud_and_nonzero(repo):
    """MUST FIRE: this is defect 2, and the wrong answer is the plausible one."""
    rc, out = run(repo, "--containing=zzz-nothing-owns-this-zzz")
    check("an unresolvable string exits non-zero", rc == 2,
          "rc=%d — a caller checking only the exit code reads this as clean" % rc)
    # Match the quiet ROW, not the word: the refusal message deliberately says
    # "This is not 'quiet'", and a bare substring test read that as the defect.
    # A guard whose text collides with the fix's own wording is the colliding
    # expected value one layer out — it fired on this file's first run.
    check("an unresolvable string does not print a quiet row",
          "quiet — nothing landed in" not in out
          and "NO TRACKED FILE CONTAINS" in out,
          "nothing was located and the output did not say so:\n%s" % out)


def t_an_empty_needle_is_refused_rather_than_answered(repo):
    rc, out = run(repo, "--containing=")
    check("an empty --containing= is refused", rc == 2,
          "rc=%d — an empty needle would census the whole tree confidently" % rc)


def t_containing_resolves_to_the_file_that_holds_the_string(repo):
    rc, out = run(repo, "--containing=not a record member: expected a field",
                  "--window=600")
    check("--containing names the file that holds the string",
          "thing.inc" in out,
          "the resolver missed the only file with the string:\n%s" % out)
    check("--containing does not drag in files without the string",
          "unrelated.inc" not in out,
          "the resolver returned files the string is not in:\n%s" % out)


def main():
    print("whoholds: an instrument aimed wrong answers, it does not error")
    repo = build_repo()
    for case in (t_a_url_form_trailer_is_seen,
                 t_a_bare_session_token_still_resolves,
                 t_a_lane_line_outranks_the_session_id,
                 t_a_string_nothing_owns_is_loud_and_nonzero,
                 t_an_empty_needle_is_refused_rather_than_answered,
                 t_containing_resolves_to_the_file_that_holds_the_string):
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
