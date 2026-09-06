---
track: P
prio: 30
type: bug
blocked-by: []
status: done
found-by: frankS (splitting the Gate off bug-p-a-generic-template-body-resolves-its-symbols-at-the-specialization-site)
summary: "MEASURED AND SETTLED. tgeneric4.pp is a `{ %fail }` row that pxx compiles and runs CORRECTLY: it prints `Unit`, exit 0, which is what the row's OWN assertion demands (`if slist.data<>'Unit' then halt(1)`). On pin v404 it printed `Program` and halted 1 -- the silent wrong answer a0780b56d fixed. The `{ %fail }` records an FPC LIMITATION the row's own comment states (\"the assembler symbol is not global\"), not a rule the language wants, and accepting what FPC rejects is not a defect. Skipped as a dialect-pass carrying the measured value and naming test_gen_declunit26 as its regression assertion."
owner: ""
---

# The row

`library_candidates/fpc-testsuite/tests/test/tgeneric4.pp` + `ugeneric4.pp`.
`ugeneric4.pp` declares `generic TList<_T>` whose `Fill` calls a
unit-implementation-private `LocalFill`; `tgeneric4.pp` declares its own
`LocalFill` and specializes. The test is `{ %fail }`.

FPC refuses at the DECLARATION, before any specialization exists:

```
ugeneric4.pp(28,4) Error: Global Generic template references static symtable
```

## What changed

`a0780b56d` fixed the compiler defect this row was accidentally covering. A
template's method body is streamed to each specialization and re-parsed there,
and it used to resolve its names in the SPECIALIZING scope — so `Fill` ran the
PROGRAM's `LocalFill`, and with no program copy the unit stopped compiling. The
body now parses as its declaring unit.

So pxx's answer to this program is no longer "silently the wrong routine". It is
**the unit's own `LocalFill`, which is what the source means.** Verified on a
corpus-free two-file reduction of exactly this shape (see the parent ticket's
2026-09-06 sections); the reduction prints `unit priv` where it used to print
`program priv`.

## Why this is a classification and not a fix

CLAUDE.md: *"Us accepting what FPC rejects is not a defect."* FPC's refusal is
FPC diagnosing a limit ITS expansion model has — a global generic cannot
reference a static symtable because of how FPC emits the expansion. pxx does not
have that limit: the parent ticket measured that a specialization written INSIDE
the declaring unit has always compiled and run correctly here, and the fix makes
the cross-unit case behave the same way.

Chasing the refusal would mean adding a diagnostic to reject a construct we
support, so the row belongs in `pxx.skip` as a deliberate dialect divergence.

**A tripwire is required, per the near-miss rule** (frankZ, 2026-09-05): a
`wontfix` on a REAL bug converts a silent wrong-code bug into a green row with an
argument attached, which is worse than a red row. That bar is met here only
because the VALUE was measured and is correct — so the skip line must say so and
must name the assertion that would catch a regression, not merely cite this
ticket.

## Why it is filed rather than done

`library_candidates/` is not fetched in every checkout. Mine has `busybox` and
`sqlite` only, so I could not run `tools/run_pascal_conformance.sh`, could not
see the row's current verdict, and could not confirm the refusal message. Every
statement above about pxx's behaviour comes from the corpus-free reduction; every
statement about FPC's comes from the parent ticket.

**Do not classify this from the reduction alone** — run the real row first. The
parent ticket's own history is the reason: this row was green for a year for a
reason unrelated to what it tests (the unit's `<_T>=` header lexed as one `tkGe`
token, and a `%FAIL` row scores ANY refusal as a pass), and nobody knew until the
parser improved.

## Gate

`tools/run_pascal_conformance.sh` with the corpus present. Read WHY the row
reports what it reports before writing the skip line.

## 2026-09-06 (frankS) — the premise is retired, not appended to

This ticket said it "needs the corpus" and could be neither run nor classified.
That was true about my checkout and it read as a property of the ticket.
frank-coordinator's measurement is the correction: the corpus is **UNFETCHED,
not scarce** — `tools/install_lib_candidates.sh fpc-testsuite`, pinned to a
commit, into a gitignored tree, and the Makefile's own SKIP line names it as the
remedy. I ran it. It took under a minute.

### The measurement the ticket was waiting for

| | pin v404 | HEAD |
| --- | --- | --- |
| `tgeneric4.pp` compiles | yes | yes |
| prints | `Program` | `Unit` |
| exit | **1** (its own `halt(1)`) | **0** |

The row asserts `if slist.data<>'Unit' then halt(1)`, so **pxx now returns the
value the test itself declares correct**, and the pin returned the wrong one.
The `{ %fail }` is not about that value at all — the row's own comment says so:

> *"It should found the LocalFill in ugeneric4, but for the moment that is not
> allowed since the assembler symbol is not global and will therefor generate a
> failure at linking time (PFV)"*

That is FPC recording a limitation of its own backend. Us accepting what FPC
rejects is not a defect (CLAUDE.md), and here it is stronger than that: we
produce the answer the row wants and FPC could not.

Skipped with the measured value and a named regression assertion —
`test_gen_declunit26`, whose row 1 fails if the program's copy ever wins again —
which is the bar this ticket set for itself.

### Three sibling rows re-measured while the corpus was there

- **`tgenfunc9.pp` — skip REMOVED, it passes.** Compiles, runs, prints 1/2/3/4,
  exit 0. It was skipped as "a generic method across a uses clause, plus
  private/protected visibility from the caller"; `1364d9542` landed both halves.
- **`tgenfunc3.pp` — skip REMOVED, it passes.** Skipped as "generic class
  functions not supported"; that spelling is fixed in the same commit.
- **`tgenfunc7.pp` — skip KEPT, reworded from `gap` to `wontfix` with
  evidence.** The generic half works: adding one `t := TTest.Create` makes the
  row exit 0. What is left is that the row calls a method on a receiver it never
  Creates, and an ORDINARY non-generic method on a nil receiver gives the same
  Runtime error 216 on this build — pre-existing and unrelated to generics, the
  same measured disposition tgenfunc5 and tgenfunc6 already carry.

### One row got WORSE and I am recording it as mine

**`tgenfunc13.pp` was rejected at the pin and is accepted at HEAD.** Not a
regression in behaviour — the pin refused it because the generic-method header
did not parse *at all*, so it was passing a `%FAIL` row **by accident rather
than by rule**, and making the header parse removed the accident.

Its disposition is tgenfunc14's, and I measured the shared premise rather than
citing it: **constraints on generic METHODS are parsed and DROPPED**, so a
CONTRADICTORY pair — declared `<T: class>`, implemented `<T: record>`,
specialized with `Integer`, which is neither — compiles and runs. The repeat FPC
forbids therefore produces no wrong answer and refuses no legal code. The skip
line carries a RE-MEASURE trigger: if constraint checking is ever added to
routines or methods, the repeated and contradictory forms stop being equivalent
and this row becomes a real FAIL again.

### Family totals

`tgeneric*`: 75 pass, **0 fail**, 29 skip (was 1 fail).
`tgenfunc*`: **6 pass** (was 4), 0 fail, 13 skip (was 14).

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit a892cd589.
