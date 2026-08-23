---
track: A
prio: 45
type: bug
blocked-by: []
status: done
summary: "`not v` on a Variant holding 12 answers False; FPC answers -13 (the bitwise complement). Silent wrong VALUE and wrong TYPE -- pxx applies logical not to every variant regardless of tag, where FPC picks bitwise-vs-logical from the operand. `v shr n` is the loud half of the same gap: `Variant arithmetic: unsupported operator`."
owner: claude-A
---

# `not` on an integer Variant answers a Boolean

Found 2026-08-23 by the Variant differential family (`fpc 3.2.2 -Mobjfpc -O1`
vs pxx `9074403c0`).

```pascal
var a, c: Variant;
begin
  a := True;  c := not a;  { pxx False    fpc False   ok  }
  a := False; c := not a;  { pxx True     fpc True    ok  }
  a := 12;    c := not a;  { pxx False    fpc -13     WRONG }
  a := 0;     c := not a;  { pxx True     fpc -1      WRONG }
end.
```

**Silent, and wrong twice over**: the value is wrong and so is the TYPE — a
program doing `mask := not flags` on variants gets a Boolean where it expected
an integer, and every downstream use of it is wrong in a way that never mentions
`not`. The boolean rows agreeing is what hides it.

Pascal's `not` is bitwise on an integer and logical on a Boolean; FPC's variant
`not` operator dispatches on the operand's tag. pxx applies the logical form to
every tag.

## The loud half of the same gap

`shr` is not implemented for variants at all:

```
a := 12; c := a shr 1;
  pascal26: error: Variant arithmetic: unsupported operator (string pending)
```

`and`, `or`, `xor`, `shl`, `div`, `mod` and unary `-` all work and all agree
with FPC (measured: 8, 14, 6, 24, 1, 2, -12 for `a=12, b=10`). So it is `shr`
alone, plus `not`'s dispatch — likely one missing arm and one wrong arm in the
same table, which is why they are filed together.

| operator | pxx | fpc |
| --- | --- | --- |
| `a and b` | 8 | 8 |
| `a or b` | 14 | 14 |
| `a xor b` | 6 | 6 |
| `a shl 1` | 24 | 24 |
| `a shr 1` | **REJECT** | 6 |
| `not a` (a=12) | **False** | -13 |
| `-a` | -12 | -12 |
| `a div b` | 1 | 1 |
| `a mod b` | 2 | 2 |

## Where to look

Both implementations, as with every variant-operator defect: `PXXVarBinOp` /
`PXXVarBinOpPas` (`compiler/builtin/`) and x86-64's `EmitVarBinOp`
(`compiler/ir_codegen.inc`). Unary `not` may take a different path from the
binary operators — find it before assuming.

**NilPy must not follow.** Python's `not 12` is `False` (truthiness), which is
exactly what pxx does today — so today's behaviour is CORRECT for NilPy and
wrong for Pascal, which makes this a lowering-seam split (`PyProgramMode` /
which helper is called), not a change of one shared rule. Check what NilPy does
with `~12` (bitwise) separately; it is a different operator.

## Gate

Track A's, plus the nine rows above matching fpc 3.2.2 on x86-64 and one
cross target, and a `.npy` row proving `not 12` still answers `False`.

## FIXED 2026-08-24 (claude-A) — and the ticket was the small half

The two symptoms filed here are real and are fixed. Reproducing them turned up
a third that neither mentions, in the same table, and it is the worst of the
three.

### What was actually wrong: the variant operator table exists twice

x86-64 lowers `IR_VAR_BINOP` to hand-emitted machine code inline
(`EmitVarBinOp`, `ir_codegen.inc`) because it is NilPy's hot path. Every other
target calls the runtime dispatch `PXXVarBinOp` (`builtin/builtinheap.pas`).
Same concept, two implementations — and only one was ever finished:

| operator | x86-64 inline | `PXXVarBinOp` (i386 / arm32 / aarch64) |
| --- | --- | --- |
| `+ - * /` `div` `mod` | yes | yes |
| comparisons | yes | yes |
| `and or xor shl shr` | **yes** | **absent** |

An operator the runtime did not implement did not raise. It fell off the end of
an `if`-chain and stored whatever `resVal` happened to hold:

```pascal
var a, b, c: Variant;
begin a := 12; b := 10; c := a and b; writeln(c); end.
```

| target | answer |
| --- | --- |
| fpc 3.2.2, pxx x86-64 | `8` |
| pxx i386 | `-524095488` |
| pxx arm32 | `1082138624` |
| pxx aarch64 | `4358436` |

The same four numbers for `or`, `xor` and `shl` — the stack slot, not the
operator. Reproduces with the pinned binary. This is the defect worth the
ticket: a silent wrong VALUE, in a shape that only appears when you leave the
one target everybody develops on, which is exactly why it survived.

### The three fixes

**1. The runtime gained the bitwise operators** — and, crucially, gained an
`else` that calls `PXXVariantError` instead of returning the stack. Shared
between the integer arm and the float arm as `VarOpIsBitwise` / `VarBitwiseInt`
rather than transcribed into both, since drift between two copies is the bug
being fixed.

**2. `shr` is no longer refused.** Pascal spells `shr` as an IDENTIFIER — there
is no `tkShr` token for it, and `ParseTerm` stores `Ord(tkIdent)` as the
operator. That convention is repo-wide (`PromoOpHelper` has an arm for it, so
does every backend's shift path), but the variant lowering was the one consumer
that did not know it, so `v shr 1` reached `EmitVarBinOp` as `tkIdent` and died
on "Variant arithmetic: unsupported operator". Fixed by NORMALISING once in
`IRLowerAST`'s variant arm — `if item = Ord(tkIdent) then item := Ord(tkShr)` —
rather than teaching the convention to the promo table and six backends
separately. In a BINOP `tkIdent` is only ever `shr`; the parser admits the
identifier solely when its text is `shr`.

**3. `not v` dispatches on the tag.** A new runtime helper `PXXVarNot`:
Boolean → logical (and the result STAYS Boolean), integer → 64-bit complement,
double → rounded then complemented, Null → Null, anything else raises.
An ordinary CALL, which is why this cost **zero per-backend codegen** — the
inline emitter on x86-64 is a speed path for NilPy's hot *binary* operators,
and a unary `not` is not one of those. NilPy is split at the lowering seam
(`PyProgramMode`) and keeps the truthiness lowering, because Python's `not 12`
genuinely IS `False`.

A fourth, smaller correction fell out of the same table: a float operand to a
bitwise op is now ROUNDED, not truncated, on both implementations —
`v(1.5) and v(10)` is 2 under FPC and answered 0 here. On x86-64 that is one
byte, `cvttsd2si` → `cvtsd2si` ($2C → $2D), which rounds half-to-even under the
default MXCSR mode, the same rule `Round` uses. `div`/`mod` keep truncating:
different operator, not an inconsistency.

### Verified

`test/test_variant_bitwise_and_not.pas`, wired into `test-core`: 20 assertions
covering the five bitwise operators, the six arithmetic siblings (so a later
edit to the table cannot quietly lose them the way the bitwise ones were lost),
`not` on an integer / zero / both Booleans / a float, and negative operands.
`ALL OK` under fpc 3.2.2 and under pxx on **x86-64, i386, aarch64 and arm32**.
riscv32 cannot compile it — `unsupported node in IR codegen: var_store`, the
already-filed [[bug-a-riscv32-codegen-has-no-variant-support]], unchanged by
this work.

NilPy re-measured against CPython on the same operators (`not`, `~`, `&`, `|`,
`^`, `<<`, `>>` including a negative operand, `not` on a float): identical, all
11 rows. Self-host fixedpoint converged in one round; `gate.sh quick` GREEN.

### Three things found here and filed, not folded in

- [[bug-a-a-boolean-variant-writes-as-1-or-0-off-x86-64]] — `writeln` of a
  Boolean Variant prints `True`/`False` on x86-64 and `1`/`0` everywhere else.
  Pre-existing (reproduces with the pinned binary), and the SAME
  two-implementations shape one level over, in the renderer. It is why this
  ticket's test reads tags and values instead of rendering Booleans.
- [[bug-p-not-of-a-builtin-round-or-trunc-call-is-logical]] — `not Round(1.5)`
  answers TRUE, i.e. `2 xor 1`, where FPC gives -3. Hit while writing
  `PXXVarNot` itself; worked around there through a local, with a comment
  naming the ticket.
- [[decide-variant-bitwise-width]] — FPC narrows a Variant to 32 bits before a
  bitwise op, so `v(-12) shr 1` is 2147483642 there; we answer -6 (64-bit,
  arithmetic, matching the `sar` x86-64 has always emitted). Three readings,
  agreeing on every non-negative operand. Parked for the user rather than
  guessed.

## Gate

`make compiler/pascal26` converged + the 20-row test on four targets + FPC +
the NilPy/CPython re-measure + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-24 — resolved, commit 6241076ad.
