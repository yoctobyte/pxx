---
prio: 70
track: P
owner: frankH
status: done
---

# bug(P): a nested N-D subscript clobbers the outer subscript's global parse state — three faces, two of them silent

`NDInfoNDims`, `NDInfoLo[]`, `NDInfoSpan[]` and `NDIdxNode[]` are global parser
scratch (`defs.inc`). Every N-D subscript loop fills them from the base array
and then holds them across a `ParseExpr` per index — and a nested N-D subscript
re-enters `NodeArrNDInfo`, refilling all four for the INNER array. Three
observable faces from one root:

| face | shape | pre-fix | fpc |
| --- | --- | --- | --- |
| refusal | `z3[1, z2[1,1], 0]` | `too many subscripts for array` | compiles |
| wrong element | `z3[1, 2, z2[1,1]]` | `112` | `122` |
| wrong row | `ShowRow(z3[1, z2[1,1]])` | `12 20 21` | `120 121 122` |

**The refusal is the NEWEST face and the least harmful one**, which inverts the
urgency a reader arriving from chess will assume. Pin v405 compiles
`chess.pas` fine, so the refusal never reached a `$(PXX_STABLE)` consumer; the
two silent faces are older and have been shipping.

The refusal is position-dependent — rank ≥ 3, and a subscript that is neither
first (parsed *before* `NodeArrNDInfo` runs) nor last (nothing reads the global
after it). That is why one line of `examples/chess/chess.pas` compiles and the
next does not.

The wrong-row face is the one that matters for the FIX SHAPE.
`BuildPartialNDIndex` computes `trailing` from `NDInfoSpan[]` and `NDInfoNDims`
*after* the loop has run, so a PARTIAL subscript gets the inner array's spans.
**A fix that only takes a local copy of the rank passes faces 1 and 2 and still
fails face 3** — it was the first shape proposed, by two of us independently.

## Fix

`NDRePrime(base)` (`pasparser_call.inc`, beside `NodeArrNDInfo`) re-primes all
four globals from the base immediately before `BuildFlatNDIndex` /
`BuildPartialNDIndex` read them. Each loop keeps a LOCAL rank and a LOCAL
`idxSave[]`, copied back after the re-prime — locals rather than one global save
slot, because the nesting has no depth limit (`z3[1, 2, z2[a[1,1], 0]]`).

Three copies of the loop, all fixed, per normalise-don't-special-case:

- `compiler/pasparser_lval.inc` — `ParseNDSubscriptTail`, both the comma and the
  `[i][j]` branch
- `compiler/pasparser_lval.inc` — `ApplyCallResultPtrSuffix`, the temp/deref path
- `compiler/pyparser.inc` — `PyParseLValueAST` (Track N's file, same root)

## What a probe built from a 1-D inner array measures, and why it is wrong

`NodeArrNDInfo` refuses rank 1 and CLEARS the globals, so **a nested subscript
of rank 1 clobbers nothing.** A probe using a 1-D inner array reads the whole
address path as clean — correct about a case this bug cannot reach. That is
exactly how face 3 was reported as unaffected while it was already live: the
first address probe used full subscripts of a 1-D inner array, where `k = rank`
makes `trailing`'s loop run zero times and land on the right answer by luck.

## Not filed: pxx accepts `i := a[0, m[0,0]]` where fpc refuses

Two subscripts on a rank-3 array assigned to an Integer. fpc says
`Incompatible types: got "Array[0..2] Of LongInt"`. Post-fix pxx still accepts
it. Per CLAUDE.md this is **not a defect**: accepting what FPC rejects is not
one, and the input is only produced by a mistake. The legitimate form of the
same path — a partial row reaching a row consumer — is face 3 above and IS
fixed and asserted.

## Verification

- `make compiler/pascal26` — `converged after 1 round(s)`, `1401414991b2`.
- Positive control at IDENTICAL sources: fix stashed, rebuilt (`d697a8a680fd`),
  `chess.pas:147` refuses, `ndpos.pas:13` refuses, wrong element `112`.
  Restored, rebuilt back to `1401414991b2`, all correct.
- Second control, pin v405: refuses the fixture at line 66 and reads face 3 as
  `12 20 21`.
- `test/test_a_nested_nd_subscript_does_not_clobber_the_outer_one.pas`, wired
  into `test-core` beside the sibling ND row: 15 rows, all three faces plus
  no-nesting controls, `fails=0 / NDNESTED OK` under pxx **and under fpc**.
- `examples/chess/chess.pas` compiles and runs to `bestmove e2e4 score 10 nodes
  40793`, native and `--target=i386`.

## The mis-lane, corrected

`regression-test-i386-chess` reads as a 32-bit row. **It is not.** Identical
error, identical line, native and cross — `test-i386` is simply the one target
the matrix builds chess for, so the label names where it was NOTICED. It was
picked as a probe for the width class CLAUDE.md calls structurally invisible on
this host and it does not serve as one.

Also: **the pin does not carry the chess face.** Pin v405 compiles `chess.pas`
fine; only post-pin `compiler/**` refuses it. So that face never reached a
`$(PXX_STABLE)` consumer, and this fix is inert-until-pinned only for the two
silent faces, which are older and DO reach the pin.

## Log

- 2026-09-06 | frankH | fixed in all three copies of the loop, with the fixture
  and both positive controls, commit a92a26917. Closed by the same commit.

Resolves `backlog/regression-test-i386-chess.md`.
