#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for the do-not-claim marker's assertion/description split.

`_NODISPATCH_RE` suppresses a ticket from `ready`/`next` when its body says it
must not be claimed. It matches TEXT, and a board that documents itself
eventually quotes its own markers -- so the mechanism decayed silently as the
board grew. Measured 2026-08-30: 14 ranked tickets matched, SIX of which never
meant it, and `next --track T` skipped its top THREE to reach the fourth. The
highest was a p70 regression cascade suppressed because its history list quotes
a commit subject that mentions the marker.

A suppressed ticket reds nothing and warns nobody -- it is simply never
offered -- which is why this needs a test rather than a reader.

The rule under test: a marker being talked ABOUT is written in code font or
inside quotes; a marker being ASSERTED is not.

Run: python3 tools/progress_nodispatch_mention_devtest.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import progress as P                                    # noqa: E402


def suppressed(body):
    return bool(P._NODISPATCH_RE.search(P.strip_mentions(body)))


def case_an_asserted_marker_still_suppresses():
    for form in ("> **NOT DISPATCHABLE — do not claim. Read this first.**",
                 "## HOLD 2026-08-14 (user) — do not claim this ticket",
                 "**NOT DISPATCHABLE.**",
                 "- **Not dispatchable — do not claim this ticket.** It is an index.",
                 "# Do not claim this ticket"):
        assert suppressed(form), f"an author's directive stopped suppressing: {form!r}"
    return "5 real spellings of an author's directive all still suppress"


def case_a_backticked_mention_does_not():
    body = ("Some prose about the board.\n"
            "`_NODISPATCH_RE` matches `NOT DISPATCHABLE` / `do not claim` and "
            "prints `[!! DO NOT CLAIM]`.\n")
    assert not suppressed(body), "describing the mechanism in code font suppressed the ticket"
    return "a ticket documenting the marker in code font is dispatchable"


def case_a_quoted_mention_does_not():
    body = 'The edge said only "not dispatchable until the question is answered".\n'
    assert not suppressed(body)
    body2 = '- `d8bdb7c5daca` fix(board): a dead "do not claim" was on top of the queue\n'
    assert not suppressed(body2), "quoting a commit subject suppressed the ticket"
    return "a quoted phrase and a quoted commit subject are both descriptions"


def case_a_quote_may_wrap_one_line():
    # Markdown wraps quotations, often with a `> ` continuation. A strictly
    # single-line pattern missed exactly this and kept a p15 ticket suppressed
    # after its blocker had been cleared.
    body = ('> was still right: the edge said *"not dispatchable until the question is\n'
            '> answered"* without presuming either answer.\n')
    assert not suppressed(body), "a quotation wrapped across a line still suppressed"
    return "a quotation that wraps one line is still read as a description"


def case_a_fenced_block_does_not():
    body = "Example board output:\n\n```\n[!! DO NOT CLAIM — the ticket says so]\n```\n"
    assert not suppressed(body), "a fenced sample of board output suppressed the ticket"
    return "a fenced sample of the banner is a description, not a directive"


def case_an_unpaired_quote_cannot_swallow_a_real_marker():
    # The bound on the quoted pattern is what makes this safe: a greedy DOTALL
    # would let one stray quote erase everything after it, and the failure would
    # be a MISSED marker -- a bad dispatch, the expensive direction.
    body = ('An unmatched " appears here and is never closed.\n\n'
            "Several paragraphs follow.\n\n" + ("filler line\n" * 40) +
            "\n> **NOT DISPATCHABLE — do not claim.**\n")
    assert suppressed(body), "an unpaired quote swallowed a genuine marker downstream"
    return "an unpaired quote is bounded and cannot erase a later directive"


def case_description_and_directive_in_one_ticket():
    # The realistic hard case: a ticket that BOTH carries a real marker and
    # explains the mechanism. The directive must win.
    body = ("> **NOT DISPATCHABLE — do not claim.**\n\n"
            "This works because `_NODISPATCH_RE` matches `do not claim`.\n")
    assert suppressed(body), "a ticket that explains its own marker lost the marker"
    return "an asserted marker survives alongside a description of itself"


def case_the_ticket_the_mechanism_was_built_for_is_still_held():
    # feature-target-wasm is why _NODISPATCH_RE exists (frankB, 2026-08-29):
    # `next` was printing a paste-ready claim line for a ticket held by a
    # standalone checkout. If a narrowing ever releases it, the narrowing is
    # wrong, and this names it rather than leaving it to a count.
    hits = list((ROOT / "devdocs" / "progress").glob("*/feature-target-wasm.md"))
    if not hits:
        return "SKIP — feature-target-wasm is no longer on the board"
    body = hits[0].read_text(encoding="utf-8", errors="replace")
    assert suppressed(body), \
        f"{hits[0].parent.name}/feature-target-wasm is no longer suppressed"
    return f"feature-target-wasm ({hits[0].parent.name}/) is still held"


CASES = [
    case_an_asserted_marker_still_suppresses,
    case_a_backticked_mention_does_not,
    case_a_quoted_mention_does_not,
    case_a_quote_may_wrap_one_line,
    case_a_fenced_block_does_not,
    case_an_unpaired_quote_cannot_swallow_a_real_marker,
    case_description_and_directive_in_one_ticket,
    case_the_ticket_the_mechanism_was_built_for_is_still_held,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = case()
        except Exception as e:
            print(f"  FAIL {name}: {type(e).__name__}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("nodispatch mention split OK" if rc == 0 else "nodispatch mention split BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
