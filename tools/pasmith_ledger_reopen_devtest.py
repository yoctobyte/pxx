#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a reopened fuzz finding must keep the history that makes it useful.

`ledger_record()` folds one divergence into `tstate/fuzz/LEDGER.json`. On a
signature that was previously marked fixed it took the `e is None` path and
REPLACED the whole entry, so `reopened_from_fixed: True` survived while every
fact about the reopen was destroyed:

  first_seed / first_sha / opened  overwritten with the new run's values
  fixed / fixed_sha                deleted
  hits                             reset to 1, not incremented
  examples                         replaced, not appended
  ticket                           reset to None

The concrete loss is a BISECT BRACKET. `fixed_sha` and the reopening sha
together bound the window in which the finding came back — exactly where a
regression hunt starts — and the ledger held both, one at a time, and then
neither.

Measured on `fpc-self_if` (found borg 2026-07-14 seed 27295 @dbbcc912715f,
fixed 2026-08-16 @42e147157b60, reopened plexus 2026-08-29 seed 91108
@eb1b200ee92f), verified against the pre-reopen revision in git rather than
taken on report.

WHY THIS SURVIVED SO LONG: the one class of finding it was observed on is
`fpc-self_*` — FPC contradicting itself between -O0 and -O2, where pxx is not
involved and no bisect was ever wanted. The erasure is generic; it was just
sitting on the finding whose loss costs nothing.

THE PRESERVE PATH ALREADY EXISTED. `recheck()` marks a finding fixed by
MUTATING the entry in place (`e["status"] = "fixed"`, `e["fixed"] = ...`). Only
the reopen edge replaced instead of mutating, so this is one path rejoining the
other rather than new machinery.

THIS GUARD WAS RUN AGAINST THE UNFIXED WRITER FIRST and failed, per the
ticket's own instruction: a guard that passes on the broken code is measuring
nothing.

Run: tools/pasmith_ledger_reopen_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "pr", os.path.join(HERE, "pasmith_run.py"))
pr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pr)

SIG = "fpc-self_if"


def _fresh():
    """A ledger holding one open finding, as the first sighting left it."""
    led = {"findings": {}, "version": 1}
    pr.ledger_record(led, SIG, "fpc-self", "if", 27295,
                     ["--seed", "27295"], "an FPC self-contradiction",
                     "dbbcc912715f")
    # Back-date to the measured instance. Two reasons, and the second matters:
    # it models the real entry (found 2026-07-14), and without it `opened`
    # would be this second's utcnow() -- so an overwrite by a reopen occurring
    # in the SAME second would be invisible and the guard would pass on the
    # broken writer. It did not, but only by luck of the clock.
    led["findings"][SIG]["opened"] = "2026-07-14T17:41:07Z"
    return led


def _fix(led, when="2026-08-16T12:05:05Z", sha="42e147157b60"):
    """What recheck() does when the example seeds stop reproducing."""
    e = led["findings"][SIG]
    e["status"] = "fixed"
    e["fixed"] = when
    e["fixed_sha"] = sha
    return led


def _reopen(led):
    return pr.ledger_record(led, SIG, "fpc-self", "if", 91108,
                            ["--seed", "91108"], "an FPC self-contradiction",
                            "eb1b200ee92f")


def _cycle():
    led = _fix(_fresh())
    news = _reopen(led)
    return led["findings"][SIG], news


# ------------------------------------------------- the original discovery --

def t_first_sighting_is_recorded():
    """Baseline: the un-reopened path must keep working."""
    e = _fresh()["findings"][SIG]
    assert e["first_seed"] == 27295 and e["first_sha"] == "dbbcc912715f"
    assert e["status"] == "open" and e["hits"] == 1
    assert e["reopened_from_fixed"] is False
    return "a first sighting opens the entry"


def t_reopen_keeps_the_original_opened_date():
    e, _ = _cycle()
    assert e["opened"].startswith("2026-07-14"), \
        "opened was overwritten with the reopen date: %s" % e["opened"]
    return "`opened` still means opened"


def t_reopen_keeps_the_first_seed_and_sha():
    """`first_*` must mean FIRST, not first-since-the-latest-reopen."""
    e, _ = _cycle()
    assert e["first_seed"] == 27295, e["first_seed"]
    assert e["first_sha"] == "dbbcc912715f", e["first_sha"]
    return "`first_seed`/`first_sha` still name the original discovery"


def t_reopen_preserves_the_bisect_bracket():
    """The whole point: fixed_sha + the reopening sha bound the window.

    A regression hunt starts from that pair. Wherever it is kept, both halves
    must be recoverable from the entry after the reopen.
    """
    e, _ = _cycle()
    blob = repr(e)
    assert "42e147157b60" in blob, \
        "the fixed_sha (last-known-good) was destroyed by the reopen"
    assert "eb1b200ee92f" in blob, \
        "the reopening sha is not recorded on the entry"
    return "the last-good and the reopening sha both survive"


def t_reopen_increments_hits():
    e, _ = _cycle()
    assert e["hits"] == 2, \
        "hits reset instead of incrementing: %s" % e["hits"]
    return "a reopen counts as a hit"


def t_reopen_appends_the_example_rather_than_replacing():
    e, _ = _cycle()
    seeds = sorted(x["seed"] for x in e["examples"])
    assert seeds == [27295, 91108], \
        "the original reproducer was discarded: %s" % seeds
    return "both reproducers are kept"


def t_reopen_keeps_the_ticket_link():
    """Not in the filed table, and worse than the bracket when it bites.

    A signature someone has already filed a ticket for loses the link on
    reopen, so the reopened finding looks untriaged and gets triaged again.
    """
    led = _fresh()
    led["findings"][SIG]["ticket"] = "bug-t-some-real-ticket"
    _reopen(_fix(led))
    e = led["findings"][SIG]
    assert e["ticket"] == "bug-t-some-real-ticket", \
        "the ticket link was erased by the reopen"
    # ...and the STATUS must stay paired with it. ledger_ticket() keeps those
    # two together, and both count as open for throttling, so handing back a
    # ticket slug beside status "open" would split a fact from its evidence in
    # a second field -- the exact defect this fix is about.
    assert e["status"] == "ticketed", \
        "reopened with a ticket link but status %r" % e["status"]
    return "a ticket link and its status both survive a reopen"


def t_reopen_reports_itself_as_news():
    """A reopen IS news — something that was fixed came back."""
    _, news = _cycle()
    assert news is True
    return "a reopen returns True, like a first sighting"


def t_reopen_is_open_and_flagged():
    e, _ = _cycle()
    assert e["status"] == "open"
    assert e["reopened_from_fixed"] is True
    return "the entry is open again and says it reopened"


def t_a_plain_second_hit_is_not_a_reopen():
    """The non-fixed path must be untouched by the fix."""
    led = _fresh()
    news = pr.ledger_record(led, SIG, "fpc-self", "if", 55555,
                            ["--seed", "55555"], "n", "cafebabe0000")
    e = led["findings"][SIG]
    assert news is False, "an ordinary repeat hit was announced as news"
    assert e["hits"] == 2 and e["reopened_from_fixed"] is False
    assert e["first_seed"] == 27295
    return "an ordinary repeat hit still just counts"


TESTS = [t_first_sighting_is_recorded,
         t_reopen_keeps_the_original_opened_date,
         t_reopen_keeps_the_first_seed_and_sha,
         t_reopen_preserves_the_bisect_bracket,
         t_reopen_increments_hits,
         t_reopen_appends_the_example_rather_than_replacing,
         t_reopen_keeps_the_ticket_link,
         t_reopen_reports_itself_as_news,
         t_reopen_is_open_and_flagged,
         t_a_plain_second_hit_is_not_a_reopen]


def main():
    rc = 0
    print("ledger-reopen devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("ledger-reopen OK" if rc == 0 else "ledger-reopen BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
