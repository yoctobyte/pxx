---
track: A
prio: 45
type: audit
status: open
found: 2026-08-29
found-by: claude-N
---

# `TypeKind = tyRecord` is not a guard, and 20 reads use it as one

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
