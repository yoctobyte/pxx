---
track: P
prio: 48
type: feature
blocked-by: []
summary: "`High(QWord)`, `Low(UInt64)`, `High(NativeUInt)` and `High(PtrUInt)` are rejected at compile time — the const evaluator carries Int64, which cannot hold 2^64-1. Every other integer type name folds. Idiomatic FPC code that spells a machine-word bound this way does not compile."
status: done
owner: unassigned
---

# The const evaluator cannot carry an unsigned 64-bit bound

- **Track P** (`OrdinalTypeBound` / the fold pipeline in `parser.inc`).
- Split out 2026-08-20 from `bug-p-str-of-a-qword-formats-it-signed`, where a
  probe hit it; the refusal itself dates from
  `bug-p-high-low-reject-the-64-bit-type-aliases` (2026-08-16) and is
  deliberate.

## Repro

```pascal
writeln(High(QWord));      { pascal26: error: undefined variable (QWord) }
writeln(High(NativeUInt)); { same }
writeln(High(PtrUInt));    { same }
writeln(High(UInt64));     { same }
```

FPC answers `18446744073709551615` for all four. Every OTHER integer type name
folds correctly in pxx today — Integer, Int64, LongWord, Word, Byte, ShortInt,
SmallInt, Cardinal, LongInt, NativeInt, PtrInt, Boolean, Char — measured.

## Why it is refused rather than wrong

`OrdinalTypeBound` returns the bound in an `Int64`, and `ASTIVal` is an `Int64`.
2^64-1 does not fit; storing it as -1 and tagging the literal `tyUInt64` would
print correctly (the write paths dispatch on signedness) but would fold WRONG
the moment the value entered const arithmetic — `High(QWord) div 2` would be 0,
not 2^63-1. The previous session chose the honest refusal, and that call stands
until the evaluator can represent the value.

## What the fix actually is

A representation change in the const evaluator, not a missing table row: carry
an unsigned flag alongside the `Int64` (or a 128-bit intermediate) and teach
the fold operators to respect it. Then the four names are one table row each.

## Scope check before starting

Grep the fold sites (`TryConstHighLowValue`, `TryFoldHighLowType`,
`OrdinalTypeBound`, the binop folder) — the flag has to reach every one of them
or the refusal is better than a partial answer.

## Outcome — 2026-08-27

Done as the ticket described — *"a representation change in the const evaluator,
not a missing table row"* — and its scope-check instruction was the load-bearing
part: *"the flag has to reach every one of them or the refusal is better than a
partial answer."* It does.

### The flag, and where it stops mattering

The unsignedness rides the **existing** `CEOrdTk` channel (added 2026-08-26 for
[[bug-p-the-constant-evaluator-erases-an-ordinals-type]]), so no new mechanism
was introduced — the channel that already carried "this fold produced a Char /
a Boolean / an enum" now also carries "this fold produced a QWord".

Only **seven** operations differ between signed and unsigned on two's
complement, and only those seven branch: `div`, `mod`, `shr`, and the four
ORDERED relationals. `*`, `+`, `-`, `and`, `or`, `xor`, `shl`, `=` and `<>` are
bit-identical and are left exactly as they were — which is why every signed
constant in the tree still folds byte-for-byte and the self-host fixedpoint
converged in one round at every step.

Sites the flag reaches, all measured:

- `OrdinalTypeBound` — the four names answer at last (`-1` is the exact bit
  pattern of 2^64-1, which is *why* the caller must know the kind).
- `TryConstHighLowValue` — publishes `CEOrdTk` at all three of its
  `OrdinalTypeBound` arms.
- `TryFoldHighLowType` — already stamped `ASTTk` with `btk`, so the expression
  side needed nothing.
- `ConstEvalFactor` — the bitwise `not` arm (unsigned survives it: a
  complemented qword is still a qword), and the integer-CAST arm, which is the
  *other* way into unsigned folding: `qword(high(int64))` is how FPC's
  `constexp.pas:329` spells it.
- `ConstEvalTerm`, `ConstEvalAdd`, `ConstEval` — the operations above, plus
  propagation through the ones that do not need it, without which
  `High(QWord) - 1 > 0` would compare signed one level later.
- the named-const read-back in `ConstEvalFactor` and the declaration site in
  `ParseConstSection` — `const A = High(QWord); B = A > 5` is TRUE, and
  `WriteLn(A)` prints 18446744073709551615 rather than -1. The Int64-widening
  arm could never have covered this: 2^64-1 looks like -1 to its range test.

### What the corpus caught, which is the real find

Folding these names at all opened a hole that had been invisible: **FPC's
`tarray5.pp` flipped from pass to accepted-invalid.**

```pascal
{ %fail }
mem : array[0..high(ptruint)] of byte;   { "doesn't fit in the address range" }
```

`ParseArrayDimBounds` declares `lo, hi: Integer` and assigns `ConstEval`'s Int64
to them, so the bound truncated in silence. And the unsigned reading is the
subtle half: `High(PtrUInt)` arrives as the bit pattern **-1**, which reads as a
perfectly ordinary `array[0..-1]` — an empty array, entirely legal. *Only the
kind separates 2^64-1 from -1*, which is exactly why this could not have been
checked before this feature existed.

`array[0..High(Int64)] of Byte` had the same hole open the whole time and was
accepted, allocating nothing and letting the program index into whatever
followed.

Both are refused now. The rule is not a new one — the index-TYPE arm ten lines
above already said *"a 4-billion-element static array is a mistake, and FPC's
own targets reject most of them too"* and raised an error; the RANGE spelling of
the same thing simply never got it. The cap is the representation's own: both
bounds must fit a 32-bit signed Integer and the element count must too. ZenGL's
`array[0..High(LongWord) shr 1 - 1]`, the largest real declaration in any corpus
here, is exactly 2147483647 elements and stays legal (verified).

### Measured

- `test/test_const_unsigned_64bit_fold.pas` (+ `.expected`, wired into
  `test-core`) — 20 rows byte-identical to `fpc -O- -Mobjfpc` 3.2.2: the four
  names, `div`/`mod`/`shr`/`shr 63`, both orderings, a named unsigned const read
  back, the cast route in, bitwise `not`, and a five-value **signed control row**
  that none of this may move.
- `test/test_array_range_too_large_fail.pas` (%fail, wired) — the `tarray5.pp`
  shape, asserting rc=1, the diagnostic, and that no binary is produced.

### Gate

`make compiler/pascal26` byte-identical (a15df9df365c) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 (tarray5 back to a correct %fail) ·
c-conformance 220/0 · fgl 7/7.

### Corpus effect, and the next wall

FPC's `constexp.pas:321` — `if (bb<>0) and (high(qword) div bb<aa) then`, the
expression this ticket was opened against — folds. `cutils`, `cstreams` and
`cclasses` all now get past it and stop at a `noreturn` procedure directive
(`constexp.pas:93`), which is a procedure-modifier gap and not filed yet; it is
one line of surface, not a feature. The `operator :=` exact-match wall
([[bug-p-an-implicit-conversion-operator-needs-an-exact-type-kind-match]]) sits
behind that.

## Log
- 2026-08-27 — resolved, commit f9c4d55e5.
