# `SizeOf(...)` (and const-intrinsics) not accepted by the compile-time ConstEval

- **Type:** feature (parser — const evaluation, Track A)
- **Status:** DONE 2026-07-04 (free-function/const path; method-param path is
  the separate [[feature-default-params-on-methods]])
- **Owner:** —
- **Opened:** 2026-07-04 (isolating the `fgl` "generics" wall; see
  [[fpc-lcl-compile-probe]])

## Problem

`SizeOf(x)` is a compile-time constant in FPC, usable anywhere a constant is —
including a **default parameter value**:

```pascal
constructor Create(AItemSize: Integer = sizeof(Pointer));   { FPC: fine }
```

pxx rejects it: `error: not a constant`. Literal / arithmetic / named-const
defaults already work (`= 10`, `= 2*512`, `= K`) — only `SizeOf` (and, by the
same gap, the other const-foldable intrinsics like `Ord`/`Low`/`High`/`Length`
of a static type) is missing from the **compile-time** evaluator.

Root: the AST expression path (`ParseFactor`, ~parser.inc:4408) fully resolves
`SizeOf(TypeName|var|arr[i])` to an `AN_INT_LIT`, but the separate compile-time
integer evaluator `ConstEvalFactor` (the `tkIdent` branch at ~parser.inc:6430)
has no `sizeof` case, so it falls through to `Error('not a constant')`
(parser.inc:6454). Default-param values evaluate via `ConstEval`
(`defaultVal := ConstEval`, ~parser.inc:13870), so they hit this gap.

This is `fgl.pp`'s second wall (`TFPSList.Create(AItemSize: Integer =
sizeof(Pointer))`), after the hint-directive gap
([[feature-hint-directives-deprecated-platform]]).

## Isolated repro

```pascal
function F(a: Integer; b: Integer = sizeof(Integer)): Integer;
begin F := a + b; end;   { pascal26: error: not a constant }
```

(`= 2*512` and `= K` compile fine.)

## Fix (Track A, parser.inc)

Add a `sizeof` case to `ConstEvalFactor` (~parser.inc:6430) that parses
`sizeof(TypeName)` / `sizeof(Pointer)` and returns the type's byte size at parse
time — reusing the type-size resolution `ParseFactor`'s `sizeof` branch already
has (factor it into a shared `ResolveSizeOfConst`). Minimal viable scope =
`sizeof(TypeName)` and `sizeof(Pointer)` (what default params use); extend to
`sizeof(var)`/`sizeof(arr[i])` if a consumer needs it. Consider the sibling
const-intrinsics (`Ord`/`Low`/`High`) in the same pass since they share the gap.

## Acceptance

- `= sizeof(Pointer)` / `= sizeof(TypeName)` default params compile and yield the
  right size.
- `fgl.pp` advances past this wall (next: `uses types` unit dependency).
- Self-host byte-identical; `make test` green; regression `.pas` with a
  sizeof-default param.

## Resolution (2026-07-04)

`ConstEvalFactor` (parser.inc ~6430) now has a `sizeof` case: `SizeOf(TypeName)`
resolves via `ParseTypeKind` → `TypeSize`/`RecSize` (covers
`sizeof(Pointer)`/`sizeof(Integer)`/`sizeof(TRec)` etc.). So `= sizeof(...)` works
in a const and in a **free-function** default-parameter value; verified against
`test/test_hint_sizeof.pas`. Self-host byte-identical.

Not folded here (rare in a const context; the AST path in `ParseFactor` handles
them at runtime): `sizeof(variable)` / `sizeof(arr[i])`.

**Note:** `sizeof` in a **method/constructor** default param still fails —
because method param lists don't accept ANY default value (not sizeof-specific).
That is the separate [[feature-default-params-on-methods]], which is what `fgl`'s
`TFPSList.Create(AItemSize: Integer = sizeof(Pointer))` actually needs.
