#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a placeholder the regex cannot see is still reported by something.

bug-t-a-wrapped-resolve-citation-is-invisible-to-both-check-and-fill. frankC
wrote an ordinary wrapped Log line:

    - 2026-08-30 — reproduced at HEAD before claiming (all three cells), fixed,
      resolved, commit PENDING-COMMIT.

It matched NEITHER progress.py's PENDING_RE nor sync.sh's fill. `check` reported
no pending resolves; sync printed "pushed 1 commit(s), all verified on origin"
with no `filled` line — which is exactly what a ticket with nothing to fill looks
like — and the literal stayed in the file. Not unfilled. **Unseen**, in all three
places anyone would look.

WHY A SECOND REGEX WOULD BE THE WRONG FIX, and why this file tests a substring:
the 2026-08-29 bug was the same one rotated. Then, the fill was sed literals
covering fewer spellings than PENDING_RE, so `check` counted what fill could not
fill and **the mismatched numbers were the alarm**. Aligning them was right — and
it retired a differential test that had been running free on every input. Two
divergent implementations of one predicate are an oracle; consolidating them
deletes it, and nothing announces that. The replacement must share no assumption
with the regex, so it is `grep -F`.

SCOPE IS THE WHOLE DESIGN, and section 3 is the guard that pins it. Run over the
tree, a literal search fires on the seven files that merely DISCUSS the
placeholder — the exact false-positive set that cost two lanes an evening. It
looks only at ticket files THIS RUN'S COMMITS TOUCHED, so it fires once, on the
sync that resolved the ticket, and never again.

SECTION 5 IS THE ONE THAT EARNS ITS KEEP, and it exists because the first cut of
this guard shipped and failed on its own commit. Condition (a) asked whether
`pending` had named the file BEFORE the fill and whether the literal is present
NOW — and a ticket that carried a real placeholder AND quotes the placeholder in
its write-up satisfies both while being perfectly healthy. It cried FILL FAILED
at a successful fill. Every fixture here had one or the other; the bug lives only
where a file has both, so nothing short of running it could have caught it.
Condition (a) now re-asks `pending` AFTER the fill, which is the only honest form
of "still owed".

TWO CONDITIONS, tested separately because conflating them hides the interesting
one: `pending` named the file and the literal survived (the fill is broken —
exit 1), versus `pending` never named it (the regex may be blind, or the line is
prose — warn and print the line, exit 0). A false positive must never carry an
exit code, or it teaches people to ignore the real one.

Run: python3 tools/sync_citation_guard_devtest.py
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SYNC = (ROOT / "tools" / "sync.sh").read_text(encoding="utf-8")
sys.path.insert(0, str(ROOT / "tools"))
import progress                                                    # noqa: E402

fails = []

WRAPPED = ("- 2026-08-30 — reproduced at HEAD before claiming (all three cells), "
           "fixed,\n  resolved, commit PENDING-COMMIT.\n")
FLAT = "- 2026-08-30 — resolved, commit PENDING-COMMIT.\n"
PROSE = ("The ticket keeps the literal PENDING-COMMIT forever, and nothing "
         "anywhere says so.\n")


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-62s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def sh_func(name):
    """Lift the function out of sync.sh verbatim — never a copy of its logic."""
    m = re.search(r"^%s\(\) \{\n.*?^\}\n" % re.escape(name), SYNC, re.S | re.M)
    if not m:
        raise AssertionError("sync.sh has no %s()" % name)
    return m.group(0)


def run_guard(cwd, tickets, still_owed, resolved=()):
    """Run verify_citations_landed for real, with a stub `progress.py pending`.

    The function asks `pending` AFTER the fill, so the stub is what makes the
    two conditions distinguishable — and it has to be a real subprocess,
    because that call is the thing under test. `$(dirname "$0")` is `.` under
    `sh -c`, so the stub goes in cwd.
    """
    stub = pathlib.Path(cwd) / "progress.py"
    payload = "".join("%s\tdeadbee\n" % f for f in still_owed)
    stub.write_text("import sys\nsys.stdout.write(%r)\n" % payload)
    script = (
        "PLACEHOLDER='PENDING-COMMIT'\n"
        "manifest_tickets='%s'\n" % "\n".join(tickets)
        + "manifest_resolved='%s'\n" % "\n".join(resolved)
        + sh_func("verify_citations_landed")
        + "\nverify_citations_landed\n")
    r = subprocess.run(["sh", "-c", script], cwd=cwd, capture_output=True,
                       text=True, timeout=60)
    return r.returncode, r.stderr
def ticket(td, rel, body):
    p = pathlib.Path(td) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("---\nstatus: done\n---\n\n# t\n\n## Log\n" + body)
    return rel


def main():
    print("1. the bug is real: PENDING_RE cannot see a wrapped citation")
    check(progress.PENDING_RE.search(FLAT) is not None,
          "it sees the flat form...")
    check(progress.PENDING_RE.search(WRAPPED) is None,
          "...and is blind to the same citation wrapped",
          "this is the defect, not a design choice")
    check(progress.PENDING_RE.search(PROSE) is None,
          "and blind to prose too, which is deliberate and must stay")

    with tempfile.TemporaryDirectory(
            dir=os.environ.get("TESTMGR_TMP") or os.environ.get("TMPDIR")
            or "/tmp") as td:
        wrapped = ticket(td, "devdocs/progress/done/bug-wrapped.md", WRAPPED)
        flat = ticket(td, "devdocs/progress/done/bug-flat.md", FLAT)
        prose = ticket(td, "devdocs/progress/done/bug-about-the-tool.md", PROSE)
        clean = ticket(td, "devdocs/progress/done/bug-clean.md",
                       "- 2026-08-30 — resolved, commit deadbeef1.\n")

        print("2. ...and the substring guard sees it anyway")
        rc, err = run_guard(td, [wrapped], [], [wrapped])
        check("bug-wrapped.md" in err, "the wrapped ticket is named", err.strip()[:60])
        check("resolved, commit PENDING-COMMIT" in err,
              "and the LINE is printed, so a reader settles prose-vs-real at a glance")
        check(rc == 0,
              "exit 0 — the push succeeded and reporting it as failed is the "
              "other failure mode", "rc=%d" % rc)

        print("3. SCOPE: it looks at this run's tickets, not the tree")
        rc, err = run_guard(td, [clean], [], [clean])
        check(rc == 0 and err.strip() == "",
              "silent when the run's own ticket is properly cited")
        check("bug-wrapped" not in err and "bug-about-the-tool" not in err,
              "even though both sit in the same tree, unmentioned by this run")
        rc, err = run_guard(td, [], [])
        check(rc == 0 and err.strip() == "",
              "and a run that touched no ticket at all says nothing")

        print("4. prose is reported, never as an error — the seven false positives")
        rc, err = run_guard(td, [prose], [], [prose])
        check("bug-about-the-tool.md" in err,
              "a ticket discussing the placeholder is still named...")
        check(rc == 0, "...but never carries an exit code", "rc=%d" % rc)
        check("if it is" in err and "prose" in err,
              "and the message tells the reader how to decide")

        print("5. BOTH in one file — the case that broke this guard live")
        both = ticket(td, "devdocs/progress/done/bug-about-and-resolved.md",
                      "- 2026-08-30 — resolved, commit deadbeef1.\n\n"
                      "The write-up quotes `PENDING-COMMIT` while explaining "
                      "it, five times over.\n")
        rc, err = run_guard(td, [both], [], [both])
        check(rc == 0, "a filled citation beside prose is NOT a fill failure",
              "rc=%d" % rc)
        check("FILL FAILED" not in err,
              "which is what the first cut got wrong, on its own commit")
        check(err.strip() == "",
              "and, since its quotes are backticked, it is not named either",
              "the bare-only rule removes what the scope split could not")

        print("6. the OTHER condition: STILL OWED after the fill")
        rc, err = run_guard(td, [flat], [flat], [flat])
        check(rc == 1, "that one exits non-zero", "rc=%d" % rc)
        check("FILL FAILED" in err, "and says the fill is at fault, not the ticket")
        check("bug in the fill" in err and "hand-edit" in err,
              "and warns against hand-editing around it")
        rc2, err2 = run_guard(td, [wrapped], [], [wrapped])
        check("FILL FAILED" not in err2,
              "while the unseen case is NOT reported as a fill failure — "
              "conflating them would hide the interesting one")

        print("7. a file the run touched and then removed is not an error")
        rc, err = run_guard(td, ["devdocs/progress/done/gone.md"], [],
                            ["devdocs/progress/done/gone.md"])
        check(rc == 0 and err.strip() == "",
              "a renamed or deleted ticket is skipped, not reported missing")

    print("8. the silent sibling: resolved this push, citing nothing")
    with tempfile.TemporaryDirectory(
            dir=os.environ.get("TESTMGR_TMP") or os.environ.get("TMPDIR")
            or "/tmp") as td:
        hand = ticket(td, "devdocs/progress/done/bug-hand-resolved.md",
                      "- 2026-08-30 — fixed with guards; resolved.\n")
        cited = ticket(td, "devdocs/progress/done/bug-cited.md",
                       "- 2026-08-30 — resolved, commit 62dd38d65.\n")
        keyed = ticket(td, "devdocs/progress/done/bug-keyed.md",
                       "commit: b78e8f9bc\n\n- 2026-08-29 — fix landed.\n")
        held = ticket(td, "devdocs/progress/done/bug-placeholder.md", FLAT)

        rc, err = run_guard(td, [], [], [hand])
        check("bug-hand-resolved.md" in err and rc == 0,
              "a hand-typed Log line with no sha is nudged, exit 0", "rc=%d" % rc)
        check("not a commit" in err and "correctly uncited" in err,
              "and the message says an uncommitted resolution is legitimate",
              "caution 3, in the text a person actually reads")

        for name, f in (("Log form", cited), ("frontmatter form", keyed)):
            rc, err = run_guard(td, [], [], [f])
            check(err.strip() == "", "silent on a real citation: %s" % name,
                  err.strip()[:60])

        rc, err = run_guard(td, [held], [], [held])
        check("resolved this push, citing no commit" not in err,
              "a ticket still holding the placeholder is the FILL's, not the nudge's")

        for pre in ("regression", "decide", "grant"):
            g = ticket(td, "devdocs/progress/done/%s-x.md" % pre,
                       "- 2026-08-30 — closed on the verdict.\n")
            rc, err = run_guard(td, [], [], [g])
            check(err.strip() == "",
                  "%s-* is not nudged — its resolution IS a verdict" % pre,
                  "23 of 43 live hits were these")

        print("9. THE FAMILY INDEX — touched on most pushes, never resolved")
        idx = ticket(td, "devdocs/progress/backlog/feature-a-a-refusal.md",
                     "The coordinator relayed: 7 PENDING-COMMIT tickets, 2 false "
                     "positives.\n\nuncited and silent. Strictly worse than "
                     "PENDING-COMMIT, which at least greps.\n")
        rc, err = run_guard(td, [idx], [], [])
        check(err.strip() == "" and rc == 0,
              "narrative prose in a touched-but-unresolved file is silent",
              "this fired on EVERY coordinator push before the split")

        print("9a. and a resolved ticket that merely QUOTES the placeholder")
        quoted = ticket(td, "devdocs/progress/done/bug-about-citations.md",
                        "- 2026-08-30 — resolved, commit deadbeef1.\n\n"
                        "It kept `PENDING-COMMIT` forever, and **PENDING-COMMIT** "
                        "is loud.\n")
        rc, err = run_guard(td, [quoted], [], [quoted])
        check(err.strip() == "" and rc == 0,
              "backticked and bolded occurrences do not count — a citation is bare",
              "the last false positive the scope split could not reach")
        bare = ticket(td, "devdocs/progress/done/bug-bare.md",
                      "- 2026-08-30 — fixed,\n  resolved, commit PENDING-COMMIT.\n")
        rc, err = run_guard(td, [bare], [], [bare])
        check("bug-bare.md" in err,
              "while a BARE wrapped citation still reports — frankC's exact shape")

        print("10. SCOPE again — editing a resolved ticket is not resolving it")
        rc, err = run_guard(td, [hand], [], [])
        check(err.strip() == "" and rc == 0,
              "in manifest_tickets but not manifest_resolved -> silent",
              "otherwise every write-up appended to an old ticket nags")

    print("11. the wiring, in sync.sh itself")
    check("verify_citations_landed" in SYNC.split("fill_pending_commits\n")[-1],
          "the guard runs AFTER fill_pending_commits, not before")
    check("'devdocs/progress/*/*.md'" in SYNC,
          "manifest_tickets uses the */*.md glob, so README.md is out of reach",
          "the same glob fill_pending_commits depends on")
    check(SYNC.count("PLACEHOLDER='PENDING-COMMIT'") == 1,
          "the literal has exactly one definition in this file")
    check("grep -qF" in SYNC,
          "and the search is a fixed-string grep, sharing nothing with PENDING_RE")
    check(SYNC.count("pending_seen") == 0,
          "the pre-fill recording is gone, not left dead beside its replacement")
    check("still_owed=$(python3" in SYNC,
          "and condition (a) re-asks `pending` AFTER the fill, not before")
    check("--no-renames" in SYNC,
          "manifest_resolved disables rename detection",
          "a git mv backlog/->done/ is R, and --diff-filter=A would miss it")
    check("--diff-filter=A" in SYNC,
          "and asks for ADDED files, so an edit to an old ticket is not a resolve")

    print("\n  %d guard(s), %d FAIL" % (39, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
