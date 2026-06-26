# ConstEval: typed casts + 64-bit folding in const initializers

- **Type:** feature (compiler, parser/ConstEval)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20
- **Priority:** low

## Problem

A `const` initializer cannot fold an expression containing an `Int64()` (or other
typed) cast, nor 64-bit-width arithmetic:

```pascal
const
  D_MANT = (Int64(1) shl 52) - 1;   { ConstEval error: "SVal = Int64" }
```

The identical expression is legal as a `var` initializer or a runtime assignment,
because those go through the normal typed expression path. ConstEval is the
limited sibling that chokes. Surfaced while writing `compiler/builtin/softfloat.pas`
(worked around with a tiny `function: Int64` returning the mask).

This is **standard Object Pascal** — FPC and Delphi both fold constant typecasts
and `shl`/`shr` in const expressions, including 64-bit. So it's an FPC-compat gap
(relevant to `feature-mimic-fpc`), not a dialect extension. ISO Pascal is the
strict one; PXX is FPC-seeded.

## Why it's more than "accept the cast"

The real work is giving ConstEval a **typed value model**:

- Track the operand type during folding, in particular Int64 vs the default
  integer width. Today `1 shl 52` would overflow a 32-bit fold even if the cast
  token parsed, so a result mask like `(1 shl 52) - 1` needs 64-bit evaluation.
- Handle a typecast node in ConstEval: `Int64(expr)`, `LongWord(expr)`, etc.
  evaluate the inner expr then reinterpret/extend to the cast type's width.
- Keep overflow behaviour matching the runtime path (wrap, not error) so a
  hand-written const equals what the equivalent var would hold.

Bounded but it touches ConstEval's core (its value representation). Scope it to
integer typecasts + integer ops first; float const-folding is a separate axis.

## Workarounds (today)

- `var` initializer instead of `const`, or
- a small `function: Int64` returning the value (what softfloat.pas does), or
- a 64-bit hex literal if the lexer accepts it (`$FFFFFFFFFFFFF`) — but that path
  has had its own >32-bit-hex bugs (see bug-64bit-shift-xor-literal-gaps).

## Acceptance

`const X = (Int64(1) shl 52) - 1;` and `const Y = LongWord($80000000);` fold to the
correct 64-/32-bit values, byte-identical self-host preserved (reseed via
`make bootstrap` if codegen-adjacent), and a regression test in test/ exercising a
few typed-cast const forms.

## RESOLVED 2026-06-20 (Track A)

ConstEval now folds integer typecasts. Added ConstIntCastWidth (maps Int64/
UInt64/NativeInt/Integer/Cardinal/Word/Byte/ShortInt/... to width+signedness,
via CaseEqual so it stays callable before LowerCase is declared) and
ConstApplyCast (reinterprets to the cast width using subtraction + decimal
literals — avoids the `not Int64()` / hex-width folding pitfalls). The cast
clause sits at the top of ConstEval: `<typename> ( expr )` evaluates the inner
const then masks/sign-extends. 64-bit folding (shl/shr/and/or/xor) was already
present, so `(Int64(1) shl 52) - 1` now folds to 4503599627370495.

Verified: Int64(1) shl 52, (Int64(1) shl 52)-1, Integer(300), Byte(257)=1,
Word(-1)=65535, ShortInt(200)=-56, Cardinal(-1)=4294967295. Byte-identical
self-host, make test green; test/test_const_typecast.pas added.

LANDMINE noted: inside ConstEval, a recursive call must be written `ConstEval()`
with parens — a bare `ConstEval` in an assignment RHS is the function result var
under the self-host semantics (it silently does not recurse).
