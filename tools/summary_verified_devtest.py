#!/usr/bin/env python3
"""`claim` prompts a re-verify, `verified` records one, and CLAIM NEVER STAMPS.

WHY THIS EXISTS
===============

Measured 2026-09-19 (`decide-whose-job-is-it-to-notice-a-ticket-has-gone-stale`):
five stale ticket SUMMARIES were found by hand in one day across two lanes,
every one of them with a CORRECT body. Detection was measured before anything
was built and it largely does not work -- a body-says-done text rule has recall
1 of 5 on the real cases and precision 0 of 7 on the live board, because PARTIAL
COMPLETION IS THE NORMAL CASE AND IS TEXTUALLY INDISTINGUISHABLE FROM STALENESS.
So the remedy that landed is not a check: `claim` puts the summary in front of
the seat, and `verified` lets that seat record the outcome.

THE THIRD CASE IS THE POSITIVE CONTROL AND IT IS THE REASON FOR THE FILE
========================================================================

A feature shaped like this rots in exactly one direction: somebody makes `claim`
stamp `verified:` itself, because it looks like a convenience and it removes a
step. That would be a date recording "a seat was TOLD to check" while reading as
"a seat checked" -- and it would certify the very thing the field exists to
measure, silently, in the flattering direction. Nothing else in the repo can see
that: the field would be present, well-formed, and current on every claimed
ticket.

`t_claim_does_not_stamp_verified` is the case that must FAIL if that happens. It
is drawn from the population the question is about (a real ticket through the
real `cmd_claim`), and it asserts an ABSENCE, which cannot be produced by
accident the way a refusal can.

`t_verified_lands_on_a_frontmatter_only_ticket` is the second control, aimed at
the OTHER documented failure in this write path: `set_field` prefers a `- **X:**`
bullet and no ticket has a `Verified` one, so this exercises the frontmatter
insert -- the exact branch that, for `Owner`, once wrote the file back BYTE FOR
BYTE UNCHANGED while printing success (2026-07-31, two agents did the same work).
A guard that only checked the print would pass through that.

No fixture anywhere: every assertion reads bytes back off disk after running the
real command, because the whole failure mode here is a fixture agreeing with its
author.

AND NOTHING HERE ASSERTS HOW THE OUTPUT IS FORMATTED. The first version of the
summary row matched a phrase from the middle of the summary and failed on
arrival: the block is wrapped for the terminal and the phrase straddled a line
break. That assertion was written from a prediction about formatting -- an axis
that is invisible in the source you write the assertion from -- and it would
have pinned the wrap width rather than the property. The rows reassemble the
wrapped lines and assert that the summary ARRIVED. See the note at that check
before shortening it.
"""
import argparse, importlib.util, io, re, sys, tempfile
from contextlib import redirect_stderr
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("pg", HERE / "progress.py")
pg = importlib.util.module_from_spec(spec)
sys.modules["pg"] = pg          # dataclasses resolve types via sys.modules
spec.loader.exec_module(pg)

fails = []

SUMMARY = ("This summary is the only part anyone reads and it carries the prio "
           "into the ranker.")


def check(name, cond, detail=""):
    print("  %-4s %s%s" % ("ok" if cond else "FAIL", name,
                           "" if cond else " -- " + detail))
    if not cond:
        fails.append(name)


def _reassemble(err):
    """Join the wrapped `claim:      ` body lines back into one string."""
    out = []
    for line in err.splitlines():
        m = re.match(r"^claim:\s{4,}(\S.*)$", line)
        if m:
            out.append(m.group(1).strip())
    return " ".join(out)


def _board(tmp, slug, folder="backlog-core", verified=None):
    """A throwaway progress tree with one frontmatter-only ticket in it."""
    root = Path(tmp)
    pg.PROG = root / "devdocs" / "progress"
    pg.ROOT = root
    for d in ("backlog-core", "working", "done", "decided", "unfinished",
              "blocked", "urgent", "rejected", "low-prio", "known-incompat",
              "rainy-day"):
        (pg.PROG / d).mkdir(parents=True, exist_ok=True)
    fm = ["---", "track: A", "prio: 50", "type: bug", "status: backlog",
          'owner: ""', "blocked-by: []", f'summary: "{SUMMARY}"']
    if verified:
        fm.append(f"verified: {verified}")
    fm += ["---", "", "# A ticket", "", "Body text.", ""]
    p = pg.PROG / folder / f"{slug}.md"
    p.write_text("\n".join(fm), encoding="utf-8")
    return p


def _claim(tmp, slug, folder="backlog-core", verified=None):
    """Run the real cmd_claim; return (stderr, path of the claimed ticket)."""
    _board(tmp, slug, folder, verified)
    buf = io.StringIO()
    args = argparse.Namespace(cmd="claim", slug=slug, owner="frankS")
    with redirect_stderr(buf):
        try:
            pg.cmd_claim(args)
        except Exception as e:                      # a git call in a bare tmpdir
            print(f"(claim raised {type(e).__name__})", file=sys.stderr)
    return buf.getvalue(), pg.PROG / "working" / f"{slug}.md"


def t_claim_prints_the_summary_and_the_two_outcomes(tmp):
    err, _ = _claim(tmp, "bug-a-a-throwaway")
    # The summary itself, not a reference to it: a pointer the seat has to go
    # open is the step that does not happen after dispatch.
    #
    # REASSEMBLED, NOT MATCHED AS A SUBSTRING. The first version of this row
    # asserted a phrase from the middle of the summary and FAILED -- the block
    # is wrapped for the terminal, so the phrase straddled a line break. That
    # assertion was written from a prediction about formatting, and it would
    # have pinned the wrap width rather than the property under test. What
    # matters is that the whole summary ARRIVED; how it is folded is not this
    # guard's business.
    #
    # DO NOT "SIMPLIFY" THIS BACK TO A SUBSTRING MATCH. It will pass on the day
    # you write it -- you will pick a phrase that happens to sit inside one
    # line -- and redden the next time the summary text, the terminal width or
    # the "claim:      " prefix changes by a character. A phrase straddling a
    # wrap is invisible in the source the assertion was written from, which is
    # what made the first version of this row look correct.
    check("claim prints the whole summary text",
          SUMMARY in _reassemble(err),
          f"reassembled block was: {_reassemble(err)!r}")
    check("claim names the still-true command",
          "progress.sh verified bug-a-a-throwaway" in err,
          "no `verified` command offered")
    check("claim says to fix it in the FIRST commit",
          re.search(r"FIRST commit", err) is not None,
          "no instruction for the not-true branch")


def t_claim_reports_never_verified_and_then_the_date(tmp):
    err, _ = _claim(tmp, "bug-a-never-checked")
    check("unverified ticket reads NEVER", "last verified: NEVER" in err,
          f"got: {[l for l in err.splitlines() if 'last verified' in l]}")
    err2, _ = _claim(tmp, "bug-a-checked-once", verified="2026-09-01")
    check("a stamped ticket reports its date",
          "last verified: 2026-09-01" in err2,
          f"got: {[l for l in err2.splitlines() if 'last verified' in l]}")


def t_claim_does_not_stamp_verified(tmp):
    """POSITIVE CONTROL. Must fail if `claim` ever writes the field itself.

    A date written by the command that PROMPTS the check certifies the check
    instead of measuring it, and does so on every claimed ticket at once.
    """
    _, path = _claim(tmp, "bug-a-not-stamped")
    fm, _b = pg.parse_frontmatter(path.read_text(encoding="utf-8"))
    check("claim leaves `verified:` absent",
          "verified" not in fm,
          f"claim stamped verified={fm.get('verified')!r} -- a seat was TOLD to "
          f"check and the field now says it DID")

    # And the field must not survive a claim of a ticket that had one: a claim
    # is a new seat, so an old date is INFORMATION (shown above) and must not be
    # silently refreshed.
    _, path2 = _claim(tmp, "bug-a-stale-stamp", verified="2026-08-01")
    fm2, _b2 = pg.parse_frontmatter(path2.read_text(encoding="utf-8"))
    check("claim does not refresh an old `verified:`",
          fm2.get("verified", "") == "2026-08-01",
          f"claim rewrote verified to {fm2.get('verified')!r}")


def t_verified_lands_on_a_frontmatter_only_ticket(tmp):
    """The write path `set_field` once no-opped on, read back off disk."""
    import datetime as _dt
    slug = "bug-a-stamp-me"
    path = _board(tmp, slug)
    buf = io.StringIO()
    with redirect_stderr(buf):
        try:
            pg.cmd_verified(argparse.Namespace(cmd="verified", slug=slug))
        except Exception as e:
            print(f"(verified raised {type(e).__name__})", file=sys.stderr)
    today = _dt.date.today().isoformat()
    fm, _b = pg.parse_frontmatter(path.read_text(encoding="utf-8"))
    check("verified writes today's date into the frontmatter",
          fm.get("verified", "") == today,
          f"frontmatter reads verified={fm.get('verified')!r}, wanted {today}")
    # It must not have damaged the field every other reader keys on.
    check("verified leaves the summary intact",
          fm.get("summary", "") == SUMMARY,
          f"summary is now {fm.get('summary')!r}")
    check("verified says what it recorded", today in buf.getvalue(),
          "the command was silent about the date it wrote")


def t_a_ticket_with_no_summary_prints_nothing(tmp):
    """No summary, no prompt -- a block of advice about an empty string is the
    cry-wolf shape this decide measured and refused."""
    root = Path(tmp) / "nosum"
    pg.PROG = root / "devdocs" / "progress"
    pg.ROOT = root
    for d in ("backlog-core", "working"):
        (pg.PROG / d).mkdir(parents=True, exist_ok=True)
    slug = "bug-a-headless"
    p = pg.PROG / "backlog-core" / f"{slug}.md"
    p.write_text("---\ntrack: A\nprio: 50\nstatus: backlog\n---\n\nBody.\n",
                 encoding="utf-8")
    buf = io.StringIO()
    with redirect_stderr(buf):
        try:
            pg.cmd_claim(argparse.Namespace(cmd="claim", slug=slug,
                                            owner="frankS"))
        except Exception:
            pass
    check("no summary means no re-verify block",
          "A TICKET IS A CLAIM WITH A DATE ON IT" not in buf.getvalue(),
          "printed the prompt with nothing to show")


TESTS = (t_claim_prints_the_summary_and_the_two_outcomes,
         t_claim_reports_never_verified_and_then_the_date,
         t_claim_does_not_stamp_verified,
         t_verified_lands_on_a_frontmatter_only_ticket,
         t_a_ticket_with_no_summary_prints_nothing)


def main():
    print("summary-verified devtest (%d cases)" % len(TESTS))
    for t in TESTS:
        with tempfile.TemporaryDirectory() as tmp:
            t(tmp)
    if fails:
        print("summary-verified FAILED: " + ", ".join(fails))
        return 1
    print("summary-verified OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
