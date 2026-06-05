# Dialect

PXX compiles a subset of Object Pascal. For language reference use the
[FPC docs](https://www.freepascal.org/docs.html); this page lists the major
features PXX supports and the extras/switches specific to PXX.

A lot of what PXX does is "just" Object Pascal that behaves the way Free Pascal
would — and matching FPC is itself a high bar, so it is worth stating plainly
what already works alongside the PXX-specific extras.

## Supported language surface

- Programs and units, qualified `UnitName.Symbol` lookup.
- Integer, Boolean, `Char`, `Single`/`Double`/`Real`/`Extended`, enums, sets,
  arrays, records, typed pointers.
- `AnsiString`: always usable inline; opt-in heap-backed refcounted mode under
  `{$define PXX_MANAGED_STRING}` (see [Not Stable](not-stable.md)).
- Dynamic arrays (`array of T`) with `SetLength`/`Length`, copy-on-write, and
  scope-exit cleanup — as locals, and as record/class fields.
- `if`, `case`, `while`, `for`, `repeat`, `break`, `continue`.
- Procedures, functions, `var`/`const` params, overloads.
- Classes: fields, methods, single inheritance, virtual/override (VMT),
  properties, visibility sections, `inherited`, `class of` metaclass.
- Generics via explicit named specialization (see below).
- Operator overloading for class/record operands.
- Exceptions: `try/except`, `try/finally`, `raise`, typed `on E: T do`, re-raise.
- Published RTTI and `.lfm` (Lazarus form) streaming into a component tree;
  a stock GTK3 helloworld compiles unmodified — see [`developer/gui.md`](developer/gui.md).

## Frontends and interop

One IR and backend, several source languages:

- **Pascal** — the primary, broadest frontend.
- **Nil Python (`.npy`)** — a Python-shaped static dialect compiled to native
  code (no interpreter).
- **C subset** — local `.c` files compiled into the same output.
- **BASIC** — early/experimental.

C libraries can be used two ways: direct `external` binding to a shared library,
or importing supported C headers so declarations come from the header instead of
hand-written `external` lines. Nil Python can drive a C library (e.g. `sqlite3`)
directly — see [`developer/c-interop.md`](developer/c-interop.md) and
[`developer/wrapper-free-c-from-nil-python.md`](developer/wrapper-free-c-from-nil-python.md).

## Type inference and inline `var` (PXX extras)

Two non-FPC conveniences, both **on by default** (disable per the flags below):

- **Inline `var` declarations** — a `var` statement may appear anywhere in a
  block, not only in the routine's top `var` section. It is scoped to its block.
- **Auto-typed variables** — a `var` with an initializer infers its type. Spell
  the type as `auto` or omit it entirely. Inference needs an initializer.

```pascal
begin
  var i := 0;              { inferred Integer, declared inline }
  var name: auto := 'Pi';  { explicit auto keyword }
  var x: Double := 3.14;   { inline, explicit type }
  for i := 1 to 10 do ...
end;
```

## Where we're headed (not all of this works yet)

This is the kind of program PXX is aiming at — a single source blending a
generic library list, an overloaded operator, a managed dynamic array, and
auto-typed inline variables:

```pascal
program showcase;

uses collections;

type
  TVec = record
    X, Y: Integer;
  end;
  TIntList = specialize TList<Integer>;

operator + (a, b: TVec): TVec;
begin
  Result.X := a.X + b.X;
  Result.Y := a.Y + b.Y;
end;

var
  list: TIntList;
  i: Integer;
begin
  list := TIntList.Create;
  for i := 1 to 5 do
    list.Add(i * i);

  var total := 0;                  { auto-typed, declared inline }
  for i := 0 to list.Count - 1 do
    total := total + list.Get(i);
  writeln('sum of squares: ', total);

  var a: TVec; var b: TVec;
  a.X := 1; a.Y := 2;
  b.X := 3; b.Y := 4;
  var c := a + b;                  { overloaded operator, inferred type }
  writeln('vector sum: ', c.X, ',', c.Y);
end.
```

**Honesty note:** this does not fully work today. The generic list and the
inline/auto-typed integers compile and run (`sum of squares: 55`), but
assigning an overloaded-operator result into an *inferred* variable
(`var c := a + b`) currently miscompiles — the second field is lost, so the
program prints `vector sum: 4,0` instead of `4,6`. Treat the blend above as the
target, not a promise. Use explicitly typed variables for overloaded-operator
results until this is fixed.

## Compiler identity

`{$ifdef PXX}` is true under PXX; `{$ifdef FPC}` is false (reserved for real
FPC). `PXX` is built in and cannot be undefined. `{$mode objfpc}` / `-Mobjfpc`
are accepted markers, not full mode emulation.

## Source directives

| Directive | Default | Effect |
| --- | --- | --- |
| `{$NESTEDCOMMENTS ON\|OFF}` | off | Nest `{ }` and `(* *)`. |
| `{$CSTYLECOMMENTS ON\|OFF}` | off | Recognize `/* ... */`. |
| `{$CASESENSITIVE ON\|OFF}` | off | Case-sensitive identifiers in this source. |
| `{$STRICT_OVERLOAD ON\|OFF}` | off | Require `overload;` on every overloaded variant. |
| `{$THREADSAFE ON\|OFF}` | off | Atomic refcounts for managed strings/arrays. |
| `{$PACKRECORDS N}` / `{$ALIGN N}` | 8 | Record field alignment (`1`/`2`/`4`/`8`/`16`/`normal`). |
| `{$R name}` / `{$R *.lfm}` | — | Queue an embedded resource (`*` = current unit base). |

Conditional compilation supports `{$define}`/`{$undef}`,
`{$ifdef}`/`{$ifndef}`/`{$else}`/`{$endif}`, `{$if}`/`{$elseif}` over a small
expression subset (`defined(NAME)`, bare symbols, `not`/`and`/`or`, parens,
`0`/`1`), and `{$include}` (one level deep, active branches only).
`{$warning}`/`{$message}`/`{$error}` fire in active branches. Valued defines and
macro replacement are not implemented. Unknown directives are accepted as
comments.

## Command-line switches

Beyond `-dNAME`/`-uNAME` and `-Mobjfpc` (see [Command Line](cli.md)):

| Flag | Effect |
| --- | --- |
| `--strict-overload` / `--permissive-overload` | Toggle the overload rule above. |
| `--threadsafe` | Atomic refcounts (same as `{$THREADSAFE ON}`). |
| `--no-auto-var` / `-fno-auto-var` | Disable auto-typed variables. |
| `--no-lazy-var` / `-fno-lazy-var` | Disable inline `var` declarations. |
| `--dump-rtti` | Print generated RTTI tables while still emitting the executable. |

## Generics

Explicit named specialization (no `Max<Integer>(a, b)` call-site sugar):

```pascal
generic function Max<T>(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;
specialize Max<Integer> as MaxInt;

type
  generic TList<T> = class
    FItems: array of T;
    procedure Add(v: T);
  end;
  TIntList = specialize TList<Integer>;        { type-section form }
specialize TList<AnsiString> as TStrList;      { top-level form }
```

See [Not Implemented](not-implemented.md) and [Not Stable](not-stable.md) for
boundaries.
