---
track: P
prio: 40
type: bug
blocked-by: []
summary: "`procedure P(const a: array of string = 'x')` compiles clean, and calling `P` with no argument prints a pointer as a length (435728179526). The default-value check reads Params[i].TypeKind without also testing IsArray — and an open-array parameter records its ELEMENT kind in TypeKind — so it sees a string parameter and demands a string literal. The array-constructor spelling `= ['x']` is correctly rejected, but with the same wrong reason: `a string parameter's default must be a string literal`. FPC rejects both."
status: new
owner: ""
---

# A default value is accepted on an open-array parameter

- **Type:** bug (frontend, parameter declaration checking) — **Track P**.
- **Filed:** 2026-08-29 by the wasm32 lane, on `origin/master` at `7aba316be`.
  Target-independent; the native x86-64 build is what prints the garbage.

## Symptom

```pascal
program DefOA2;
procedure P(const a: array of string = 'x');
begin
  writeln(Length(a));
end;
begin
  P;
end.
```

```
ok: defoa2  [code=61793B  data=1976B  bss=42452B  procs=130]
435728179526
```

Compiles clean; prints a pointer read as a length. FPC rejects the declaration.

The *sensible* spelling is rejected, which is how this stayed hidden:

```pascal
procedure P(const a: array of string = ['x']);
```
```
pascal26:2: error: a string parameter's default must be a string literal
```

Note the diagnostic. It refuses the array constructor **because it wants a
string** — it has already decided this is a string parameter. The refusal is
right by accident and its stated reason is the bug, so anyone who hit it would
have written `= 'x'` to satisfy the compiler and walked straight into the
garbage above. A message that names a cause here is naming the discriminator,
not the defect.

## Root cause

`ParseArrayCtorAST` (pasparser_lval.inc:3354) documents the convention: an
open-array parameter's `TypeKind` **is the element type**, with `IsArray`
carrying the "it is an array" half. For `const a: array of string` that is
`tyAnsiString`.

The default-value check reads `TypeKind` alone, so an open-array-of-string
parameter is indistinguishable from a `string` parameter at that test, and
`ProcParamDefaultIsStr` is set on a parameter that is an array. `ir.inc`'s
default-parameter arm then materialises the frozen literal into a hidden
managed temp and passes it where the callee expects an open array's
`(data, count)` pair — hence a pointer where the length belongs.

## Fix

Test `IsArray` alongside `TypeKind` at the default-value check, and reject the
declaration outright: an open-array parameter cannot carry a default in this
dialect, so both `= 'x'` and `= ['x']` should be errors, with a message that
says *that* rather than asking for a string literal.

Deliberately NOT fixed in `ir.inc` in the same pass. Adding the `IsArray` guard
to `ir.inc`'s default-parameter arm would take the other branch and pass a raw
frozen literal to an open-array parameter — one wrong lowering traded for
another. The lowering has no correct behaviour to fall back on because the
declaration should never have been accepted; the frontend is where this ends.

## Same shape, one level up

This is the identical `TypeKind`-without-`IsArray` confusion as
`bug-a-open-array-of-string-arg-spilled-through-a-managed-string-temp` (Track
A, fixed 2026-08-29), which was six sites in `ir.inc` asking whether an
argument needs an owning managed-string temp. That one was found because
wasm32 type-checks the store and refused; this one was found while deciding
whether its default-parameter arm needed the same guard. **Worth a grep for
other readers of `Params[...].TypeKind` that never consult `IsArray`** — two
independent instances in two layers is the "three is a design flaw" counter at
two.

## Gate

Track P's: `make compiler/pascal26` (the byte-identical self-host fixedpoint)
plus both spellings above rejected with a message that names the real reason,
plus a `{%FAIL}` conformance case if one fits.
