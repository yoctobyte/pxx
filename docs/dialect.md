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

## Compiler identity

`{$ifdef PXX}` is true under PXX; `{$ifdef FPC}` is false (reserved for real
FPC). `PXX` is built in and cannot be undefined. `{$mode objfpc}` / `-Mobjfpc`
are accepted markers, not full mode emulation.

## PXX switches

| Switch | Default | Effect |
| --- | --- | --- |
| `{$NESTEDCOMMENTS ON}` | off | Nest `{ }` and `(* *)`. |
| `{$CSTYLECOMMENTS ON}` | off | Recognize `/* ... */`. |
| `{$CASESENSITIVE ON}` | off | Case-sensitive identifiers in this source. |
| `{$strict_overload on}` | off | Require `overload;` on every overloaded variant. |

Conditional compilation supports `{$define}`/`{$undef}`,
`{$ifdef}`/`{$ifndef}`/`{$else}`/`{$endif}`, and `{$if}`/`{$elseif}` over a
small expression subset (`defined(NAME)`, bare symbols, `not`/`and`/`or`,
parens, `0`/`1`). `{$warning}`/`{$message}`/`{$error}` fire in active branches.
Valued defines and macro replacement are not implemented.

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
