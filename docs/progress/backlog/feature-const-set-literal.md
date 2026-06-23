# Set literal in a `const` declaration (`const S = [1,2,3]`)

- **Type:** feature (parser/const) — Track A
- **Status:** backlog
- **Opened:** 2026-06-23
- **Found by:** differential probe vs FPC.

## Problem

A set constant fails to parse ("unexpected token"):

```pascal
const S = [1,2,3];           // pxx: error;  fpc: ok
type TS = set of 1..9; const S: TS = [1,2,3];   // also fails
begin if 2 in S then ... end.
```

A `var` set assigned a `[...]` literal at runtime works; only the `const`
declaration form is unhandled.

## Fix

Accept a `[...]` set literal as a constant initializer and store it as a
compile-time set bitmask (the same blob a runtime set uses), so `in` / set ops
read it like any set constant. Needs const-expr handling for set literals + a
const-set data representation. Gate: `make test` + FPC oracle.

## Findings (2026-06-23, scoping pass — NOT a quick win)

Tried the cheap route — reuse the typed-const Pending/Local-init machinery to
emit `S := [1,2,3]` (the runtime set-literal assignment that already works for a
`var`). It does **not** work: a deferred AST node does not survive from parse to
`CompilePendingGlobalInits` — `CompileAST` resets `ASTNodeCount` to 0 after each
init and the body parse reuses the node pool, so a parse-time `AN_SET_LIT` index
points at clobbered nodes by the pre-`main` emit. (The scalar/array/record const
paths dodge this by storing only a *value*/span and rebuilding the leaf node at
emit time — a whole set literal can't be reduced to one Int64.)

So this needs an actual const-set data representation, roughly:
1. At parse time, `ConstEval` each element (and `lo..hi` ranges) into a 32-byte
   (256-bit) mask; ranges must be compile-time. Bake the mask into `Data[]`
   (rodata) — same blob shape `IR_SET_LIT` already emits.
2. Record the const in a new const-set table: name -> Data offset (+ the set's
   enum/element info for typed `: TS` forms; plain-integer set for the untyped
   `const S = [..]` form).
3. `ParseFactor`: resolve a const-set name to a set value whose address is that
   `Data[]` offset, so `x in S` / set ops read it like any 32-byte set operand.
   (Cheaper alt: allocate a normal `tySet` BSS var + a pending init that
   `IR_SET_COPY`s the baked blob into it — but pending-init has no whole-set/
   byte-offset store today, so that path needs a new init kind too.)

Estimate: ~half a day, not a parser one-liner. The array/multidim/record const
initializers (done 2026-06-23) were cheap because they decompose into per-leaf
scalar assignments; a set does not.

## Related (Track B, noted)

`LowerCase`/`UpperCase`/`Trim` (string-case SysUtils funcs) are also missing
without `uses sysutils` — those belong in `lib/rtl/sysutils` (Track B), unlike
the System char/ordinal intrinsics (UpCase, Succ/Pred/Odd, Abs/Sqr, Pos) added
this session.
