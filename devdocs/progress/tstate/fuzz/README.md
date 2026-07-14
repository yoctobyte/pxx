# tstate/fuzz — the findings ledger

`LEDGER.json` is the fuzzer's memory. One entry per **signature**, not per seed.

## Why it exists

A single `case`-selector defect once produced **639 report files here**, one per seed,
every one of them the same bug. A fuzzer that reports one bug 639 times is not finding
bugs; it is finding *a* bug, loudly — and the pile buries the only number that matters:
**distinct causes per CPU-hour**. Those 639 files are now one ledger entry with
`hits: 639`; the raw pile is in git history if anyone ever wants it.

## Signature

    <who-disagrees>_<what-it-sits-on>        e.g.  pxx-vs-fpc_case
                                                   pxx-self_virtcall
                                                   pxx-reject_copy-dynamic-array-copy

The left half is the disagreement class (`pxx-vs-fpc`, `pxx-self`, `fpc-self`,
`pxx-cross`, `pxx-reject`, `fpc-reject`, `pxx-crash`, `pxx-timeout`). The right half is
the **statement kind** the trace-diff blames (pasmith stamps a `kind=` on every trace
checkpoint), or — for a rejected program — a slug of the compiler's own diagnostic.

Coarse **on purpose**. A finer key (the statement's operators, a hash of its text)
splits one bug back into hundreds of "distinct" signatures, because the surrounding
expression differs every seed. That is the failure mode we removed, dressed up as
precision. The cost — two simultaneous bugs in the same construct read as one — is paid
down by keeping up to 5 example seeds per entry, and by the entry reopening the moment
the first bug is fixed.

## Statuses, and what they do to the fuzzer

| status | meaning | fuzzing |
| --- | --- | --- |
| `open` | found, not yet triaged | **throttled** (`fuzz_backoff_minutes`, default 90) |
| `ticketed` | filed into the owning lane, not fixed yet | **throttled** — still unfixed |
| `fixed` | its example seeds no longer reproduce | **full speed** |

A **new** signature stops the running slice on the spot (`--stop-on-new`): file it, hand
it to the owning lane, don't spend the remaining minutes re-finding it. A **known** one
is counted and never re-filed.

Every idle tick **rechecks** the unfixed entries against the current sha and marks the
ones that stopped reproducing as `fixed` — so fuzzing goes back to full speed **by
itself, on the fix**, not when a human remembers to re-enable it. Throttling on an open
finding is only honest if something notices the fix without being asked.

## Using it

    tools/pasmith_run.py --ledger devdocs/progress/tstate/fuzz/LEDGER.json --ledger-status
    tools/pasmith_run.py --ledger <path> --ledger-inplace --recheck        # after a fix lands
    tools/pasmith_run.py --ledger <path> --ticket <sig>=<ticket-slug>      # after filing

## Track T rule this encodes

**T owns the tool, never the bug.** A finding is filed into the lane that owns it
(IR/codegen → A, dialect/frontend → P, RTL/ansistring → B) and the ledger records
*which ticket*. T's job ends at a shrunk, attributed, deduplicated report.
