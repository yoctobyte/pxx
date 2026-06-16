# Routines

Procedures and functions, `var`/`const`/value parameters, and `Result`/the
function-name return all behave as in FPC. This page covers the PXX extras and
limits.

## Overloads

Multiple routines may share a name, resolved by argument types. The `overload;`
directive is **optional by default**; `--strict-overload` (or
`{$STRICT_OVERLOAD ON}`) requires it on every variant, `--permissive-overload`
relaxes it again.

## Operator overloading

`operator` definitions for class/record operands, mirroring FPC:

```pascal
operator + (a, b: TVec): TVec;
begin
  Result.X := a.X + b.X;
  Result.Y := a.Y + b.Y;
end;
```

Record-valued operator results assign into both explicit and inferred targets.
Operands wider than a machine word should be passed `const` (see
[Types](types.md) on by-value record truncation).

## Auto-typed and inline `var` (PXX extras)

Two non-FPC conveniences, **both on by default**:

- **Inline `var`** — a `var` statement may appear anywhere in a block, not only
  in the routine's top `var` section. It is scoped to its block.
- **Auto-typed `var`** — a `var` with an initializer infers its type; spell the
  type as `auto` or omit it. Inference requires an initializer.

```pascal
begin
  var i := 0;              { inferred Integer, declared inline }
  var name: auto := 'Pi';  { explicit auto keyword }
  var x: Double := 3.14;   { inline, explicit type }
  for i := 1 to 10 do …
end;
```

Disable with `--no-auto-var` / `--no-lazy-var` (or `-fno-auto-var` /
`-fno-lazy-var`).

## Generics

Explicit **named specialization** only — there is no call-site sugar like
`Max<Integer>(a, b)`:

```pascal
generic function Max<T>(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;
specialize Max<Integer> as MaxInt;          { top-level form }

type
  generic TList<T> = class
    FItems: array of T;
    procedure Add(v: T);
  end;
  TIntList = specialize TList<Integer>;      { type-section form }
specialize TList<AnsiString> as TStrList;    { top-level form }
```

## Directives on routines

Recognised: `inline`, `register`, `cdecl`, `assembler` (see
[Inline assembly](inline-asm.md)), `overload`, `external 'lib.so' [name 'sym']`
(dynamic import), and `generator` / `stackful` / `stackless` (see
[Generators](generators.md)). `inline`/`register` are accepted markers.
