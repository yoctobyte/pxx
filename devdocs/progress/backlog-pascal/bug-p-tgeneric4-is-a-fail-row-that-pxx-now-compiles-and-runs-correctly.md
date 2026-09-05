---
track: P
prio: 30
type: bug
blocked-by: []
status: backlog
found-by: frankS (splitting the Gate off bug-p-a-generic-template-body-resolves-its-symbols-at-the-specialization-site)
summary: "tgeneric4.pp is an FPC `{ %fail }` row -- the compile must be REJECTED. FPC rejects it at the declaration (`Global Generic template references static symtable`). Since a0780b56d pxx compiles it AND RUNS IT CORRECTLY: a generic template's method body now binds in its DECLARING unit, so the unit's own private helper is what runs. Under CLAUDE.md accepting what FPC rejects is not a defect, so this row wants a deliberate `pxx.skip` classification, NOT a fix -- but it is a %FAIL row, so it stays red until someone writes that classification. NEEDS THE CORPUS: library_candidates/fpc-testsuite is not fetched in every checkout (mine has only busybox and sqlite), so I could neither run nor classify it. One row, one skip line, for whoever has the corpus."
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
