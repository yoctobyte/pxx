---
slug: feature-p-the-booleannn-family-of-explicit-width-boolean-type-names
track: P
type: feature
prio: 45
status: done
created: 2026-09-06
found-by: frankB
owner: frankD
blocked-by: []
title: "`Boolean16` / `Boolean32` / `Boolean64` — the second sized-boolean family"
summary: "DONE 2026-09-09. fpc ships TWO sized-boolean families and pxx shipped one: `Boolean16`/`Boolean32`/`Boolean64` answered `unknown type`. They differ from the `*Bool` family in EXACTLY TWO things, measured: `Ord(True)` is 1 rather than all-bits-set, and the ordinal reads UNSIGNED rather than signed (`Boolean16(65535)` = 65535 where `WordBool(65535)` = -1). Everything else -- width from the name, nonzero-is-true at `if`/`not`/`WriteLn`, Low = False -- is shared. Implemented as a SECOND FAMILY BELOW the first in the SemId encoding (`SEM_PBOOL_BASE = -32`), so `SemIsBool` stays TRUE for it and `SemBoolWidth` decodes both: all TWENTY existing readers keep working untouched, and only two things are family-aware (storage signedness, True-materialisation). Fixture matches fpc 3.2.2 byte for byte on 13 rows. THREE ROWS OF THIS TICKET WERE STALE WHEN I TOOK IT and are corrected below -- the blocker was decided AND BUILT, the sibling bug is closed, and QWordBool already worked. CORPUS: the wall moves on all twelve `tthlp*` files, and they still do not compile -- they now hit a DIFFERENT wall, filed as bug-p-self-in-a-record-helper-for-a-dynamic-array-types-as-integer. That is the ticket's own 'looks like progress' warning coming true in the direction it did not predict."
---

# The `BooleanNN` family, and what separates it from `*Bool`

Measured 2026-09-09, compiler `9b2cfef2721d`, against fpc 3.2.2.

| | width | `Ord(True)` | `X(65535)` → Ord | `High` | sign |
| --- | --- | --- | --- | --- | --- |
| `Boolean16/32/64` | 2/4/8 | **1** | **65535** | 1 | **unsigned** |
| `*Bool` | 1/2/4/8 | **-1** | **-1** | -1 | **signed** |

Shared, and asserted as such: nonzero-is-true at `if`, `not` and `WriteLn`;
`Low` = False; the width comes from the name; a bound carries the named type's
width.

**The signedness row cannot fail on a small probe.** `Boolean16(200)` and
`WordBool(200)` both answer 200 — 200 fits a signed 16-bit. 65535 is the
discriminator, and this is the same trap `ByteBool`'s own comment records one
family over (200 vs 255).

## The design, and why it costs twenty readers nothing

The SemId encoding's negative space was built so an unwidened reader gets a
TRUE answer rather than a wrong one. The second family is placed **below** the
first (`SEM_PBOOL_BASE = -32`, so `Boolean16` is -34) rather than beside it, so:

- `SemIsBool` (`< SEM_BOOL_BASE`) is **true** for both — every reader that asks
  "is this a sized boolean" is already right about `Boolean16`.
- `SemBoolWidth` decodes **both**, so every reader that asks "how wide" is too.
  A single-family decoder would have returned **18** for `Boolean16` and all
  twenty would have believed it. A wrong width does not error; it sizes a store.
- Only two things are family-aware: `BoolStorageKindOf` (signedness) and the
  True-materialisation.

`BoolStorageTypeKind(SemBoolWidth(sem))` was written out at four call sites and
is family-blind. It is now one function, `BoolStorageKindOf(sem)`, so the next
family is one arm and not a fifth transcription. Same for the three
materialisation sites, now `SemBoolMaterialiseSem`.

## Three rows of this ticket were stale, and one would have stopped the work

Re-measured before starting, per this file's own "re-run the rung" rule:

- **The `blocked-by` edge was live in the frontmatter and dead in the world.**
  `decide-how-a-type-carries-an-identity-its-kind-cannot-hold` is `decided` —
  and, more than decided, **BUILT**: all four carry slices landed 2026-09-06.
- **The ORDERING HAZARD block was the thing that would have stopped me.** It
  said adding these names ships four more instances of
  `bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time`. That bug is in
  `done/`, and I measured its rows: `ByteBool`/`WordBool`/`LongBool` now match
  fpc on width, `Ord`, `WriteLn`, `not` and both branch directions. The hazard
  was real when written and is gone.
- **`QWordBool` was listed as refused and already works** — it landed with the
  sibling fix.

A hazard block is the most expensive kind of stale row: it is written to stop a
reader, it succeeds, and nothing about obeying it produces a signal.

## Two things measured on the way that were not the subject

**fpc cannot store its own `High(WordBool)`.** `wb := High(WordBool)` is
refused by fpc's *assembler* — `word value exceeds bounds
9223372036854775807` — while the same line compiles here. `SizedBoolBound`'s
comment predicted exactly that from the other direction; this is it observed.

**`QWordBool` is where the truncation coincidence stops.** fpc answers the
Int64 extremes for `High`/`Low` of every `*Bool` width and we answer True/False.
At widths 1/2/4 the extremes truncate to exactly our -1/0 *even through an
`Int64()` readout*, because the ordinal is narrower than the reader — so the two
agree and the chosen divergence is invisible at every width the original
measurement used. At width 8 there is nothing left to truncate. Both findings
are now in `SizedBoolBound`'s comment.

## The corpus claim, and what it actually bought

`uthlp.pp` declares `record helper for Boolean16` and twelve `tthlp*` files use
it — verified, not taken on trust. All twelve moved off `unknown type:
Boolean16`. **None of them compiles yet:** all twelve now stop at
`uthlp.pp:242`, `Length needs a string, an array or a PChar, not Integer`, on
`Result := Length(Self)` inside a `record helper for` a *dynamic array* type.
Filed as
[[bug-p-self-in-a-record-helper-for-a-dynamic-array-types-as-integer]].

**One name unblocked twelve files by exactly one defect.** This ticket warned
that moving a corpus wall forward "looks like progress and is not"; it meant
that about shipping the sibling bug, and the warning landed somewhere else
instead. Report the wall that moved, never the files that "now work".

## Log

- `compiler/defs.inc` — `SEM_PBOOL_BASE`, and why the family goes below.
- `compiler/util.inc` — `SemPBool`, `SemBoolIsPascal`, two-family
  `SemBoolWidth`, `PBoolStorageTypeKind`, `BoolStorageKindOf`.
- `compiler/pasparser_lval.inc` — the three names in both tables, the Pascal
  `High`, both High/Low doors, and the two findings above.
- `compiler/pasparser_expr.inc` — `SemBoolMaterialiseOp`/`SemBoolMaterialiseSem`.
- `compiler/ir.inc`, `compiler/pasparser_decl.inc` — call sites.
- `test/test_booleannn_family.pas` + `.expected` — 13 rows, `.expected` is fpc's.
- `Makefile` — `test-core` row `test_boolnn26`.
