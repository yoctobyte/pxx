---
track: A
prio: 45
type: audit
status: done
found: 2026-08-29
found-by: claude-N
owner: frankA
summary: "RESOLVED. An array-of-record symbol carries TypeKind = tyRecord (the field holds the ELEMENT kind), so 14 reads across 8 routines in three frontends used a type test that is not one. Four named accessors replace them -- SymRecOf for value resolution, SymIsRecordTyped/SymOwnRecOf/SymOwnClassIdx for the symbol's own type -- because the single accessor this ticket proposed would have been a NEW defect in all 14 (True for an array OF slices). The 14 were masked by AllocArray clearing RecName; a forced control that re-dirties it makes the pre-fix code take a file write on an array of Text. One real behaviour change with a gcc oracle: C _Generic now decays an array controlling expression, five rows fixed, two filed."
---

# `TypeKind = tyRecord` is not a guard, and 20 reads use it as one

> **RESOLVED 2026-09-01 (frankA) in `51aef8e0f`.** 14 reads at HEAD, all
> converted; the forced positive control below turns "safe because something
> else masks it" into a measurement. See the closing section.

An **array-of-record symbol has `TypeKind = tyRecord`** — the field holds the
ELEMENT kind, by design, and `ResolveNodeRec` says so in its own comment
(*"Array symbols store their ELEMENT record in `ElemRecName`, not `RecName` ...
a recurring landmine throughout this codebase"*).

So this, which reads like a type check, is not one:

```pascal
if Syms[s].TypeKind = tyRecord then
  ... Syms[s].RecName ...        { `s` may be an ARRAY of record }
```

There are **20 such reads.** They are not distributed evenly: three frontends
independently grew the same three-line predicate over the same field.

## Not urgent — say why, so the next reader does not re-panic

[[bug-a-allocarray-leaves-recname-stale-on-a-recycled-symbol-slot]] landed in
`4a3c88532` (b4), clearing `RecName` in `AllocArray` and `AllocDynArray`. That
makes these 20 reads **safe today**: the field they misread is now clean, so
they get `REC_NONE` instead of a recycled neighbour's record id.

**It does not make the guards correct.** It removes the one thing that was
dirtying the field. Anything that dirties it again — a new allocator, a new
write path, a refactor that reorders slot reuse — walks straight back into all
20, and so does any new reader written by copying one of them. That is why this
is filed separately rather than folded into the fix: a defect that a *different*
ticket's fix currently masks is exactly the kind that comes back without a
record of itself.

## The 20

| file:line | what it is |
| --- | --- |
| `rparser.inc:590,591` | `RIsSliceSym` — **the one that actually fired** |
| `rparser.inc:4309,4313` | `b = Board { .. }` aggregate assign to a plain identifier |
| `zparser.inc:275,276` | `ZIsOptSym` — character-for-character copy of `RIsSliceSym` |
| `zparser.inc:310,311` | `ZIsSliceSym` — a third copy of the same three lines |
| `pasparser_stmt.inc:494,549` | generator `for..in`: puts `RecName` on an `AN_DEREF`, so a wrong value gives `ResolveNodeRec` the wrong size → **garbage copy, silent** |
| `pasparser_stmt.inc:3107` | — |
| `pasparser_stmt.inc:6799,6800,6803,6810` | behind `DelphiMode and SymProcSig[idx] >= 0` |
| `pasparser_expr.inc:3913,3914` | (an `IsArray` test exists further up; likely fine) |
| `pyparser.inc:45249,45250` | `SizeOf` — **correct**: the array arm above it uses `ElemRecName` |
| `cparser.inc:1110` | `CExprCG` → `CGRecA`, consumed by `CGMatch` for `_Generic` selection |

Two are already known good (`pyparser`, and `pasparser_expr` has a guard outside
the window the census used). The rest were not individually cleared.

## What to actually do — and it is not "add `IsArray` in 20 places"

Twenty copies of a guard is the same smell as twenty copies of the predicate.
The shape worth considering:

- **One accessor.** `SymRecOf(idx)` returning `ElemRecName` for an array symbol
  and `RecName` otherwise, so callers stop choosing. `ResolveNodeRec` already
  does exactly this branch internally and has for a while — it is the model.
- **Then the three `Is*Sym` predicates collapse too.** `RIsSliceSym`,
  `ZIsSliceSym` and `ZIsOptSym` differ only in which `Ci[]` table they consult;
  they are one predicate with a parameter. Duplicating a *parser* across
  languages is deliberate policy
  (`the-substrate-is-ast-and-ir-not-the-parser.md`), but this is not parsing —
  it is a symbol-table question, which is shared ground and A's.

Deciding between those is the work; do not take "add a guard" as the answer just
because it is the smallest diff.

## Provenance

Census run 2026-08-29 while auditing
[[bug-a-allocarray-leaves-recname-stale-on-a-recycled-symbol-slot]] across the
frontends: 126 reads of `Syms[..].RecName`, 86 with no `IsArray`/`ElemRecName`
within ±12 lines, and these 20 narrowed by "guarded by `TypeKind = tyRecord` and
nothing else". Comments were stripped before matching — an earlier run counted
prose *describing* a call as the call itself.

## Gate

Whatever lands: `make test` + self-host byte-identical. The two repros from the
parent ticket stay the evidence — the Rust parse error (loud) and the C
`_Generic` selection (silent, diffable against gcc) — and per b4's finding, the
C one is the reliable regression: the Rust shape needs two parameters **and**
the array as `main`'s first local, and its controls cannot share a file with it.

---

## Resolved 2026-09-01 (frankA, Track A) — `51aef8e0f`

### The census, re-run rather than inherited

By ENCLOSING ROUTINE, not by a ±12-line window: 202 reads of
`Syms[..].RecName` across `compiler/*.inc` + `*.pas`; 14 of them with no
`Syms[<same var>].IsArray` or `.ElemRecName` anywhere in the routine, gated on
`TypeKind = tyRecord`. Same script on the tree after: **0 of the same 202.**
The 202 on both sides is the denominator — the zero is not a vacuous one.

| routine | file |
| --- | --- |
| `CExprCG` | `cparser.inc` |
| `ParseForInGeneratorAST` (×2) | `pasparser_stmt.inc` |
| `TextIOFileSym` | `pasparser_stmt.inc` |
| `RIsSliceSym` (×2) | `rparser.inc` |
| `RParseStatementInner` (×4) | `rparser.inc` |
| `ZIsOptSym` (×2), `ZIsSliceSym` (×2) | `zparser.inc` |

**The window aperture has a false negative, and it hid the site this ticket
calls "the one that actually fired."** `RIsSliceSym` is suppressed by an
`IsArray` in a *neighbouring routine* twelve lines away. A window answers about
PROXIMITY; the question is about SCOPE. The counts reconcile otherwise: the
table above lists the same sites, and `pasparser_expr` / `pyparser` are the two
this ticket had already cleared.

### Not one accessor — and that is the finding

This ticket proposed `SymRecOf(idx)` returning `ElemRecName` for an array so
callers stop choosing. That is right for **one** of the two questions and would
have been a NEW defect in all 14 places, in the loud direction:

- `RIsSliceSym` would answer **True for an ARRAY of slices** — the name says
  "is this symbol a slice", the accessor would ask "is its ELEMENT one".
- `TextIOFileSym` would accept `var f: array[0..1] of Text; WriteLn(f, 'x')`
  as a file write and take the array's address as a handle.

So four functions, each naming its question, in `symtab.inc`:

| | question | array answer |
| --- | --- | --- |
| `SymRecOf` | what record does this symbol's VALUE denote? | `ElemRecName` |
| `SymIsRecordTyped` | is this symbol OF record type? | False |
| `SymOwnRecOf` | ...and which? | `REC_NONE` |
| `SymOwnClassIdx` | ...as a user-class index? | `-1` |

`SymRecOf`'s one caller is `ResolveNodeRec`'s AN_IDENT arm — the branch this
ticket named as the model, now made in one place and called from there. The
branch and the id are BOTH needed because `REC_NONE` is a legitimate answer for
a record-typed symbol, so a caller wanting the branch cannot get it by testing
the id; the two `ParseForInGeneratorAST` sites use both, in that order.

The ticket's own instruction — *"do not take 'add a guard' as the answer just
because it is the smallest diff"* — turned out to apply to its own suggestion.

### The forced positive control

The 14 were safe before this commit, because `4a3c88532` clears `RecName` in
`AllocArray`/`AllocDynArray`. **A mask is not a guard, and here is the
difference, made to happen.** One scratch line, never committed — every array
symbol's `RecName` set to the `text` record id instead of `REC_NONE` — built
twice and run on `var f: array[0..1] of Text; WriteLn(f, 'x')`:

```
arm A   pre-audit guards + dirty RecName    Runtime error 9 (I/O error)
arm B   these guards     + dirty RecName    identical to the clean reference
```

Arm A took the array as a Text handle and wrote to garbage. Arm B is
byte-for-byte the clean build's answer.

**What that implies for testing, stated because it is uncomfortable:** under a
clean tree the two arms are identical, so **no file in `test/` can catch a
revert of this commit.** The control is the evidence and it lives here. A
reader who wants to re-run it needs exactly one line changed in `symtab.inc`
and two builds.

### One real behaviour change, with an oracle

`CExprCG` (C `_Generic`) had no array shape at all — the array fell through to
its `TypeKind`. Against `gcc -std=c11`, before (`e4d4f945961e`) → after:

| controlling expr | gcc | before | after |
| --- | --- | --- | --- |
| `struct S a[3]` | `struct S *` | `default` | matches gcc |
| `int b[4]` | `int *` | `int` | matches gcc |
| `char c[5]` | `char *` | `char` | matches gcc |
| `long L[2]` | `long *` | `long` | matches gcc |
| `int m[2][3]` | `default` | `int` | matches gcc |

The int/char/long rows never touched `RecName`, so the arm is **wider than the
guard that exposed it** — `CExprCG` simply had no array shape. `m[2][3]` is why
the inner dimensions are nested array levels rather than flattened: `int (*)[3]`
matches neither `int *` nor `int`, so gcc takes `default`, and a flattened
descriptor answered `int *` — a *confident* wrong selection.

`test/cgeneric_array_decay.c` (wired into `test-core`) pins all five plus two
non-array controls: gcc scores 127, the pre-fix compiler scored **96**, this
compiler scores 127.

Two rows remain unequal to gcc and are filed rather than guessed at —
[[bug-c-generic-selection-loses-an-array-elements-pointer-target-and-its-constness]]:
`int *p[2]` and `const int ci[2]` need carriers the array symbol does not have
(the element's pointer target, the element's constness). Deliberately NOT added
to the test file: a test that asserts a wrong answer teaches the next reader
that the wrong answer is intended.

### The three predicates collapsed

`RIsSliceSym`, `ZIsSliceSym` and `ZIsOptSym` were character-for-character
identical apart from which `Ci[]` table they consult. The symbol-table half is
`SymOwnClassIdx` now; each frontend keeps only its table lookup. Duplicating a
PARSER across languages is deliberate policy
(`the-substrate-is-ast-and-ir-not-the-parser.md`) — this was not parsing.

### Gate

`make compiler/pascal26`: converged, `a7e7f780b782`. `tools/gate.sh quick`:
GREEN, FPC seed canary PASS (run with `compiler/` dirty, so the canary was
live). Not `make test` as this ticket's own `Gate:` line asked: CLAUDE.md's
per-fix loop supersedes it, and the breadth is Track T's.

## Log
- 2026-09-01 — resolved, commit 51aef8e0f.
