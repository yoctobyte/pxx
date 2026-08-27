---
track: P
prio: 40
type: bug
summary: "`Low(s)` and `High(s)` on a SET variable answer 0 and -1 instead of the element type's bounds, so `for i := Low(s) to High(s)` is a silently empty loop. FPC answers 0/255 for `set of Byte`, 1/10 for `set of 1..10`, and the enum's ordinals for `set of TEnum`."
status: done
---

# `Low`/`High` of a set answer 0 and -1, not the element bounds

- **Type:** bug (silent wrong answer) — **Track P**
- **Found:** 2026-08-27, while fixing
  [[bug-p-length-low-and-high-of-a-set-answer-the-bitmask]]. Split out because
  it needs storage the compiler does not currently keep, where the rest of that
  cluster did not.

## Measured

```pascal
var s: set of Byte;      { or: set of 1..10, set of TE }
```

| expression | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `Low(s)`, `s: set of Byte` | 0 | 0 *(agrees by luck)* |
| `High(s)`, `s: set of Byte` | **-1** | 255 |
| `Low(s)`, `s: set of 1..10` | **0** | 1 |
| `High(s)`, `s: set of 1..10` | **-1** | 10 |
| `Ord(Low(s))`, `s: set of TE` | 0 | 0 *(agrees by luck)* |
| `Ord(High(s))`, `s: set of TE` | **-1** | 2 |

Silent, and it fails in the direction that hides: `for i := Low(s) to High(s)`
runs zero times rather than crashing.

`Low`/`High` on the set's TYPE NAME are a separate question and were not
measured here.

## Why it was not fixed with the rest of the cluster

The Low/High arm reaches the tail with a symbol index, and the set's element
information on that symbol is:

- `SymSetElemTk[idx]` — the element **type kind** (`compiler/defs.inc:2310`)
- `SymSetEnumId[idx]` — the enum identity, when the element is an enum

Which answers `set of Byte` (0..255 from the kind) and `set of TE` (the enum's
ordinal range). It does **not** answer `set of 1..10`: an anonymous subrange
element collapses to `tyInteger` and its BOUNDS are dropped — there is no
`SymSetElemLo/Hi`, and `AliasSetElemTk` (`defs.inc:4250`) carries only the kind
too.

So a partial fix would answer two of the three shapes correctly and the third —
the one whose bounds are most obviously *written down in the source* — with a
plausible wrong 0/2147483647. That is worse than the current uniform gap, which
at least fails the same way every time.

## Fix shape

Carry the element's bounds beside its kind. `ParseSetType`
(`pasparser_decl.inc`, the `set of <subrange>` arm) already evaluates `lo..hi`
through `ConstEvalOrdBound` and then **discards both**; the same two values need
a `SymSetElemLo`/`SymSetElemHi` pair (and the alias-table twin) to reach the
Low/High arm. `LastTypeSetElemTk` is the existing channel to extend.

Then the Low/High arm answers, in order: the retained subrange bounds, else the
enum's ordinal range via `SymSetEnumId`, else the element kind's own bounds via
`OrdinalTypeBound` — which is the same three-way the array-index arm beside it
already does for `SymArrIdxTk`/`SymArrIdxEnumId`.

## Gate

The six rows above match `fpc -O1 -Mobjfpc` 3.2.2, for a set VARIABLE and for a
`set of` alias; `for i := Low(s) to High(s)` iterates the declared range;
self-host fixedpoint byte-identical.
---

# Outcome — FIXED, 2026-08-27

Built exactly as the fix shape above describes, including the reason it was
described that way: the subrange bounds were plumbed through **first**, so the
arm never had to ship answering two shapes out of three.

## What was added

- `SymSetElemLo` / `SymSetElemHi` (`defs.inc`), beside `SymSetElemTk`, with the
  alias twins `AliasSetElemLo` / `AliasSetElemHi` and the
  `LastTypeSetElemLo` / `Hi` channel between them. `Hi < Lo` means *no subrange
  recorded*; the init is `0 / -1`.
- `ParseSetElemSpec` now **keeps** what `ConstEvalOrdBound` returns instead of
  evaluating and discarding it.
- `RegisterSetAlias` carries the pair, so a named `TSA = set of 1..10` answers
  the same as the inline spelling.
- `TryOrdinalVarBound` (`pasparser_lval.inc`) gains a `tySet` arm doing the same
  three-way it already does one level up: recorded subrange, else the enum's
  ordinal range via `SymSetEnumId`, else the element kind's own bounds via
  `OrdinalTypeBound`. An unrecorded element kind (0) returns False and keeps the
  old answer rather than inventing one. `tkOut` becomes the ELEMENT's kind, so
  the literal prints as FPC's does.

`TryOrdinalVarBound` was the right home rather than a new routine: it is already
the "Low/High of a variable" three-way, and the set case is that same question
asked one level down on the element.

## Verified

`test/test_set_low_high_element_bounds.pas` (wired into `test-core`) is
**byte-identical to the FPC 3.2.2 oracle** across eleven rows — all six rows
from the table above, plus `set of Char`, both shapes again through a NAMED set
type (which carries the element identity in the alias table, not on the symbol),
the two `for i := Low(s) to High(s)` loops that were the point (10 and 3
iterations, previously 0), and membership over the same variables as a guard
that the set representation was not disturbed.

`gate.sh quick` GREEN; Pascal conformance 346/0/170/34, C conformance 220/0,
fgl 7/7; `fpc_diff_probe` 0 new divergences.

## The open question in the ticket, answered

*"`Low`/`High` on the set's TYPE NAME are a separate question and were not
measured here."* Measured now: **FPC refuses it too.**

```
tn.pas(5,25) Error: Illegal expression
```

pxx says `undefined variable (TSA)`. Different wording, same refusal — so this
is not a gap, and under the FPC-parity ceiling the wording difference is not
one either. Nothing to file.

## Log
- 2026-08-27 — resolved, commit 42e48c869.
