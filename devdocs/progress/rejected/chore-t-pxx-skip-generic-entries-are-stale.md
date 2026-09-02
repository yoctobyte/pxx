---
track: T
prio: 45
type: chore
status: rejected
found: 2026-09-01
found-by: claude-T
owner: ""
blocked-by: []
summary: "11 of 21 generic-related entries in test/pascal-conformance/pxx.skip now meet the runner's full contract and are skipped anyway, so the conformance suite under-reports pxx by 11 tests. Two more (tgeneric15/16) now compile and fail at RUN, so their reason strings describe a gap that has moved from parse to runtime. Verified against a compiler whose srchash MATCHES the tree, with %FAIL/%NORUN honoured — a plain compile check would have wrongly called 8 more of them stale."
---

# `pxx.skip`'s generic entries are stale — the suite under-reports by 11 tests

Generic support has moved a lot (`9801b0bcb`, `78e3b6426`, and the
specialization-alias fix behind them). The skiplist did not move with it.

Verified on seven against a compiler with `srchash MATCH`, so failures and
passes are both conclusive.

## Stale — full contract met, should be un-skipped (11)

Compile-only (`%NORUN`), so compiling clean IS the whole contract:

| test | skip reason now stale |
|---|---|
| `tgenconstraint1.pp` | Delphi generic constraint syntax |
| `tgeneric48.pp` | mixed generic overloads by arity |
| `tgeneric50.pp` | hint directives on generics and specializations |
| `tgeneric62.pp` | nested `object` inside generic class |
| `tgeneric65.pp` | generic record with nested `object` |
| `tgeneric66.pp` | generic `object` with nested record |
| `tgeneric67.pp` | generic `object` with nested class |
| `tgeneric68.pp` | generic `object` with nested `object` |

Compile **and run, exit 0** — checked by running them, not just compiling:

| test | skip reason now stale |
|---|---|
| `tgeneric59.pp` | same generic name at different arity |
| `tgeneric7.pp` | generics across units + `$R` state per unit |
| `tgenfunc1.pp` | generic standalone functions + inline specialize |

## Reason string now wrong, entry still justified (2)

`tgeneric15.pp` and `tgeneric16.pp` **compile clean and fail at run (exit 1)**.
Their reasons name a declaration/parse gap ("class inheriting from
`specialize TStack<Integer>` as parent type"), and that half is closed. What
remains is a runtime failure the reason does not describe. Same shape as
`tgeneric50.pp`'s entry naming two gaps when only one was open — an entry that
is accurate about *that there is a problem* and wrong about *what it is* costs
the next reader an hour.

## Correctly skipped — do NOT touch (8)

- `tgeneric83/84/85.pp` — `%FAIL` tests. The contract is that the compile must
  be **rejected**; pxx still accepts them, so "it compiles" means still broken.
- `tgeneric21/26.pp` — `accepts-invalid`; needs a semantics judgement, not a
  compile check.
- `tgeneric14/20/30.pp` — `wontfix: dialect-pass`, deliberate divergence.

## Method note, because it nearly went wrong

The first sweep just compiled every skipped generic test and reported 21 as
newly passing. That is wrong for 8 of them: for a `%FAIL` test a successful
compile is the defect, and `wontfix` entries are deliberate. The corrected sweep
reads each file's directives and runs the non-`%NORUN` ones. **A proxy check
that ignores the contract inverts the answer for exactly the tests where the
contract is the point.**

## Why it matters

Every stale entry is coverage we have and do not count, and a gap we may
re-investigate because the list says it is open. It also feeds the noise problem
in `chore-t-fpc-conformance-noise-skews-priority` from the other side: the
suite's number is not a fair reading of conformance in either direction.

## Suggested handling

Un-skip the 11 in one commit, and re-word the 2 rather than delete them.
Not done here: this is a data change and the owner has this box on
tickets-only. The verification above is the expensive half and is reproducible —
re-run it before landing, since generics are moving daily.

## Rejected 2026-09-02 — the Track T tooling backlog was cut as a pile

Owner decision, not a judgement on this ticket individually. 73 of the 74 open
`track: T` tickets were filed between 2026-08-31 and 2026-09-02, 58 on one day.
The pile was too large to work through, and a ticket nobody will fix does not sit
neutrally: it stays in the ranker forever at zero value, which is the same
argument CLAUDE.md already makes for `rejected/` over a low prio.

Four were kept, on a purely structural test — an active umbrella, or a hard
`blocked-by:` edge from live non-T work: `umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**This is a reversible archive, not a deletion.** If one of these is refiled
later, it should be refiled with the evidence that makes it worth doing rather
than restored wholesale.
