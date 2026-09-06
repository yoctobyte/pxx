---
track: T
prio: 45
type: bug
status: backlog
found: 2026-09-06
found-by: frankuser
owner: ""
blocked-by: []
summary: "A `gate.sh` FAIL row does not say whether the failure is one THIS seat just introduced or one that was already on the tree. Those two call for opposite actions — fix it now, versus check who is already on it — and they print the identical line. Measured 2026-09-06: `fecdfe6dc` landed a silent Makefile assertion at 19:25:54 and within roughly the next hour FOUR seats found it independently (frankB fixed it; frankD fixed the same line minutes later and lost the commit as empty on the rebase; frankA found and fixed the sibling neither had covered, `5c327fbaa`; frankS reported it a fourth time). Three duplicated efforts and one rebase. gate.sh's OUTPUT is not the defect — it names the check, the file and the line, and publishes `gate: RED (exit 1)`. What is missing is provenance."
---

# A gate red does not say whether it is yours or the tree's

## What was measured

`fecdfe6dc` (2026-09-06 19:25:54) landed a bare `test "$(grep -c ... )" = 4` —
an assertion that fails printing nothing — which `tools/silent_assertion_check.py`
correctly caught from `tools/gate.sh:730`.

Inside roughly the next hour, four seats hit it:

| seat | what happened |
| --- | --- |
| frankB | fixed it |
| frankD | fixed the identical line minutes later; commit dropped as empty on the rebase |
| frankA | found the sibling neither fix had covered, `5c327fbaa` |
| frankS | reported it a fourth time, believing it lived in `tools-devtest` |

Green at `02d1ff4d7` (verified by running the lint).

## Why this is not a legibility defect in the output

Worth stating, because that was the first reading and it is wrong.
`tools/gate.sh` already does the things a legibility fix would add: each check
prints `FAIL` with its name, the offending `Makefile:<n>` and the assertion
text, and the run ends with `gate: RED (exit 1)` — the status published in the
LINE and not only in `$?`, for reasons its own trailing comment explains at
length. Every one of the four seats read the row correctly. Nothing was hidden.

## The actual gap

A seat reading `FAIL Makefile assertion check` cannot tell which of these it is:

- **a red it just introduced** — drop everything, this is yours, fix before push
- **a red already on the tree** — someone else's, possibly already being fixed

The two demand opposite responses and produce the same output. In the absence of
provenance, every seat correctly assumes the first, because assuming the second
and being wrong means pushing a red you made. So the safe default is exactly the
one that produces N duplicate fixes when N seats gate in the same window — and
the more seats are working, the more reliably it fires.

**This is the house shape:** the instrument is correct about something else. The
row is a true statement about the tree in front of the seat. It is read as a
statement about the seat's own diff, because that is what a gate is normally
telling you.

## Fix shape

gate.sh already computes a merge-base for the FPC seed canary, so the notion is
present. For any check that is a pure function of the tree (the lints — silent
assertions, forwardlint, iropname, abi_oracle, ast_slot_overloads, clone field
sets, devtest registration), running it once against the merge-base tree
answers the question directly:

- fails at merge-base too -> `FAIL (pre-existing at <base>)` — not yours
- passes at merge-base -> `FAIL (introduced by your working tree)` — yours

That is one extra invocation per lint on a checkout of the base, only on the
FAIL path, so it costs nothing on a green gate. It does not need to be perfect:
labelling even a subset of the lints removes most of the collision surface,
because the lints are where the cheap shared reds live.

Not in scope here: telling a seat that a PEER is already fixing it. That needs
cross-session state and is a different, larger ticket. Provenance alone is
enough — "pre-existing" is the signal that makes a seat ask before fixing.

## An adjacent hazard, same row

`tools/silent_assertion_check.py` (the lint, run from `gate.sh:730`) and
`tools/silent_assertion_check_devtest.py` (the devtest OF that lint, run inside
`tools-devtest`) differ by one suffix and live in one directory. The fourth
sighting was filed against the wrong one, and the argument attached to it — that
the row was hidden inside a job that had TIMED OUT — was therefore unreachable
from the evidence, while being a true and important statement in general. Two
scripts one substring apart, one gate row each, sitting beside the row four
seats had just converged on.

## What does NOT explain it

- **Not a two-day-old red.** The assertion landed at 19:25:54 the same evening.
  The two-day figure belongs to the unrelated `test-fpjson` row, whose recipe
  piped its failing compile to `/dev/null` and stored the string `"compiling
  fpjson suite runner ..."` as its reason. Do not merge the two.
- **Not seats skipping the gate's non-fixedpoint rows** — but this is weaker
  than it first looked and is recorded at its real strength. All four seats did
  read the row. That is not evidence those rows are read ROUTINELY: one of the
  four reports reading its log for `self-host fixedpoint` and the testmgr
  verdict, seeing FAIL, and only then reading what had failed — adding that a
  row it could not attribute in ten seconds might not have been followed up.
  So cheap attribution may be doing work here that the count cannot see, and a
  more expensive row could produce silence rather than four fixes. Left open
  deliberately: it would take a red nobody could place to measure, and this
  incident cannot supply one.
