---
track: T
prio: 45
type: bug
status: backlog
found: 2026-09-05
found-by: frankZ
owner: ""
blocked-by: []
summary: "Census of all 138 tools-devtest files, prompted by 9bd00df46 where a guard asserted the literal `\"$bin\"` and read a rename as a deletion. 82 read repo source text; 17 make 21 literal assertions against it; 13 of those assert a CODE-SHAPED literal — an exact assignment, dict entry or comprehension — as a proxy for a behaviour that is observable elsewhere. Every one goes RED on a reflow that changes nothing and GREEN on dead code, which is both failure directions at once. The one found so far was found by accident, because it happened to go red; the rest are in the state it was in BEFORE the rename. Clean on one axis and it is worth recording: all 9 split-anchors fail loud (IndexError), none silently returns the whole file."
---

# Thirteen devtest guards assert a code line's SPELLING as a proxy for a behaviour

## Why this census exists

`9bd00df46` fixed `tools/gate_pinned_rtl_canary_devtest.py`, which asserted the
literal string `"$bin"`. `b6212f43f` renamed that artifact to `"$work/run.bin"`
while leaving the canary compiling and running exactly as before, and the guard
reported the run step as **deleted** — loudly, blocking `make tools-devtest`
for every lane.

**It was found by accident, because it went red.** A guard in that shape that
has not yet been renamed around is green, asserts a string, and is blind to the
thing it names. `138 green` is exactly the number that stops anyone looking.

This is frankD's zero-census point applied to a guard population rather than to
a report: **an absent report line is indistinguishable from a detector that
stopped working** — and a guard asserting a literal does not go silent when it
stops covering. **It goes green.**

## The numbers, and how they were derived

Population is what the Makefile actually runs: `tools/*devtest*.py` minus
`bench_timing_devtest.py`. Classification is AST-based, not grep — a text-shaped
census of text-shaped guards would share their failure mode.

| | count |
|---|---|
| files in `tools-devtest` | 138 |
| ...that read repo SOURCE text | 82 |
| ...that probe it with a string literal | 17 |
| literal sites total | 63 |
| — parse anchors (`split`/`index`, not assertions) | 42 |
| — **assertions on source text** | **21** |
| — — **code-shaped literal** (assignment, dict entry, call, comprehension) | **13** |
| — — bare identifier | 8 |

**The 13 are the finding.** A code-shaped literal carries the source's
FORMATTING, so it breaks on a reflow that changes no behaviour, and it passes on
code that is present but dead. Both failure directions in one assertion.

The 8 bare identifiers are weaker: renaming a published JSON field IS a
behaviour change, so asserting the name is defensible. They still pass on dead
code, and they belong in the same fix when one is written.

## The thirteen

    sync_citation_guard_devtest.py    :268  "PLACEHOLDER='PENDING-COMMIT'"
    sync_citation_guard_devtest.py    :274  'still_owed=$(python3'
    sync_citation_guard_devtest.py    :279  '--diff-filter=A'
    sync_contention_devtest.py        :194  'TICKETS_FINGERPRINT=$fp'
    testmgr_pin_straddle_devtest.py   :95   'pin1 = pin_identity() if pin0 else None'
    testmgr_pin_straddle_devtest.py   :124  'j.sel or j.name for j in jobs if j.pin_built'
    testmgr_pin_straddle_devtest.py   :128  'report.get("pin_straddled")'
    testmgr_skip_reason_devtest.py    :212  '"skips": skip_summary(jobs),'
    testmgr_skip_reason_devtest.py    :300  '"skips": (report.get("skips") or {}).get("count")'
    twatch_code_stamp_devtest.py      :160  'auto-filed by Track T watcher, host %s, twatch `%s`'
    twatch_flaky_report_devtest.py    :96   '"flaky": [j.name for j in jobs if j.flaky]'
    twatch_flaky_report_devtest.py    :99   'RUN_RETRY_SIGNATURES = ("Text file busy", "ETXTBSY")'
    twatch_skip_anchor_devtest.py     :226  '"never_passed": never_passed,'

## Why none was fixed here, stated rather than implied

**The canary fix was cheap for a reason that does not generalise.** `gate.sh`'s
canary is a shell function, so "does it execute what it built" could be re-asked
*in the same medium* — collect the compiled artifacts, assert one is run at a
command position. No producer had to be driven.

These 13 assert that a **Python producer emits a field**. The behavioural
version is to call the producer and read the artefact, and in every case checked
the emitting code sits deep inside a long function that the devtest does not
already drive. `twatch_skip_anchor_devtest.py` is representative: it happily
drives `tw.diff_jobs` and `tw.reg_open`, which are small, but `"never_passed"`
is appended to `regs` inside the main sweep, which it does not.

So this is a GROUP, filed as one, and not a rewrite anyone should start in the
middle of. **Do not convert it into a suite-wide refactor.**

## Two routes, and the cheap one is not the obvious one

1. **Drive the producer.** Correct and complete: call the function, read the
   artefact, assert the key is present with the right value. Also fixes the
   dead-code direction. Cost is per-file and real, because each needs a fixture
   the file does not have.

2. **Assert against the PARSED source, not its text.** For a dict entry, ask the
   AST whether a call to `regs.append` has a key `"never_passed"`. This does not
   fix the dead-code direction, but it removes the reflow brittleness — which is
   the half that actually fired — for a fraction of route 1's cost, and it is
   the same medium the guard already lives in.

**Prefer 1 where a fixture already exists in the file; take 2 where it does
not.** Mixing them by file is correct, not inconsistent.

## The clean axis, recorded because a null result is only informative if
## somebody counted

All **9** split-anchor uses on source text index `[1]` or higher, so a moved
anchor raises `IndexError` — loud, and immediately debuggable. **Zero** use the
`.split(x)[0]` idiom, which silently returns the whole file when `x` is absent
and would hand a guard a region it never verified it found. That idiom is the
one to reject in review; it is currently not present.

## The rule this population needs

A guard's assertion must be able to distinguish a RENAME from a DELETION. If it
cannot, it will eventually report one as the other, and it does not get to
choose which direction. See `devdocs/dev/debugging-playbook.md`, "a guard can be
loudly wrong while RED".

## 2026-09-05 (frankZ) — the same instrument, one polarity over: prose read as code

This ticket's population is guards that read a code line's SPELLING and call it
a behaviour. Building the dev-library skip path I produced the mirror image and
it is worth recording here rather than in a new ticket, because it is the same
instrument failing for the same reason: **a text scan cannot tell an assertion
from a description of one.**

`tools/testmgr.py`'s `uses` detector matched, in a header COMMENT:

```
  Uses only the language surface that ALL backends support today — no classes,
  ...  output on x86-64, i386, ARM32 and AArch64 ...
```

and yielded the unit name `i386`, which resolves nowhere, which meant "this box
is missing a development package", which meant **SKIP `test_conformance_2.pas`
— the cross-portable conformance harness** — on a box that has every package.
Silently, because a skip scores passlike.

**Where this one differs from the thirteen, and it is the part that generalises:**
those guards read the RIGHT file and asked it a question it could not answer.
This read the right file and could not tell which REGION of it was source. The
fix is not a better regex — it is stripping comments and string literals before
scanning at all (`_strip_pascal_comments`), i.e. **deciding what is source
before asking what it says.** Any guard that greps a source file for a language
construct has this hole; `uses`, `type`, `var`, `begin` and `end` are all
ordinary English or ordinary prose punctuation in a comment block.

Not fixed here for the thirteen — this is one data point on the same mechanism,
filed so the census has it. The dev-library guard's own version is fixed and
carries a positive control (`tools/host_dev_lib_skip_devtest.py` section 7).
