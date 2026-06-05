# Dialect

PXX compiles a subset of Object Pascal. For language reference use the
[FPC docs](https://www.freepascal.org/docs.html); this page lists the major
features PXX supports and the extras/switches specific to PXX.

## Supported language surface

- Programs and units, qualified `UnitName.Symbol` lookup.
- Integer, Boolean, `Char`, string, `Single`/`Double`/`Real`/`Extended`,
  enums, sets, arrays, records, typed pointers.
- `if`, `case`, `while`, `for`, `repeat`, `break`, `continue`.
- Procedures, functions, `var`/`const` params, overloads.
- Classes: fields, methods, single inheritance, virtual/override (VMT),
  properties, visibility sections, `inherited`, `class of` metaclass.
- Generics via explicit named specialization (see below).
- Operator overloading for class/record operands.
- Exceptions: `try/except`, `try/finally`, `raise`, typed `on E: T do`, re-raise.
- Published RTTI and `.lfm` component streaming (GTK3 GUI).
- C interop: `external` shared-library binding and a C header/source frontend.
- Heap: `GetMem`/`FreeMem`, `New`/`Dispose`, `ReallocMem`.
- Frontends: Pascal, a C subset, and early BASIC / Nil Python.

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
