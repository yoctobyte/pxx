# Pascal Dialect And Compatibility

PXX compiles a growing Object Pascal dialect intended to remain useful beside
Free Pascal. It is not currently a complete FPC implementation.

## Compiler Identity

Compiler identity is separate from source dialect:

| Marker | Meaning in PXX |
| --- | --- |
| `{$ifdef PXX}` | True when Pascal source is compiled by PXX. |
| `{$ifdef FPC}` | False under PXX; this is reserved for actual Free Pascal compilation. |
| `{$mode objfpc}` | Accepted compatibility marker for source written in the intended dialect. |
| `-Mobjfpc` | Command-line form of the accepted mode marker. |

This permits shared source without claiming APIs or behavior belonging only to
FPC:

```pascal
{$ifdef FPC}
  { Free Pascal host implementation }
{$else}
  {$ifdef PXX}
    { PXX implementation }
  {$endif}
{$endif}
```

PXX's own bootstrap code still uses real `{$ifdef FPC}` branches where the
FPC-built seed needs host library operations and the native compiler needs its
own implementation.

## Conditional Compilation

Implemented directives:

```pascal
{$define FEATURE}
{$undef FEATURE}

{$ifdef FEATURE}
  writeln('included');
{$else}
  writeln('excluded');
{$endif}

{$ifndef FEATURE}
  writeln('not defined');
{$endif}
```

Symbols and directive names are case-insensitive. Blocks may be nested.
`PXX` is a built-in identity symbol and cannot be undefined from source or
with `-uPXX`.

Not yet implemented: conditional expressions such as `{$if ...}`, valued
defines, `{$elseif ...}`, or general FPC switch-state behavior.

## Tested Language Surface

The regression suite currently covers:

- Programs and Pascal units.
- Constants, variables, integer, Boolean, character, and string operations.
- Arrays and records.
- Procedures, functions, `var` parameters, and overload dispatch.
- `if`, `case`, `while`, `for`, `repeat`, `break`, and `continue`.
- Classes with fields and methods.
- Generic classes and generic procedures/functions using explicit specialization.
- Operator implementations for class/record operands.
- Untyped `try/except` catch-all blocks and `raise <expr>`.
- Selected C imports from Pascal `uses` clauses.

## Overloading

Routine overloads may be declared in FPC-style syntax:

```pascal
function Pick(x: Integer): Integer; overload;
function Pick(c: Char): Integer; overload;
```

By default, PXX also accepts overloaded routine variants without `overload;`.
Strict declaration checking is opt-in:

```pascal
{$strict_overload on}
```

or:

```sh
./compiler/pascal26 --strict-overload source.pas /tmp/out
```

## Generics

The supported generic function/procedure form uses explicit named
specialization:

```pascal
generic function Max<T>(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;

specialize Max<Integer> as MaxInt;
```

Class generics are supported as well. Generic call-site sugar such as
`Max<Integer>(a, b)` is not an implemented compatibility promise.

## Operator Implementations

Operator definitions are supported for class/record operands, for example:

```pascal
operator + (a, b: TPoint): TPoint;
begin
  { construct and return a point }
end;
```

Tests presently exercise `<`, `>`, `=`, and `+`.

## Exceptions

Phase 1 exception handling supports untyped catch-all handlers:

```pascal
try
  raise 42;
except
  writeln('caught');
end;
```

`except else` is also accepted as an explicit catch-all form. A raised
expression can cross procedure and unit boundaries. Typed `on E: EClass do`
handlers, `try/finally`, bare `raise;`, and exception class/message objects
are not implemented yet. `Exit` correctly removes active handler frames;
`break` and `continue` in a protected body are rejected in this phase.

## Compatibility Claim

PXX source compatibility should be stated narrowly:

- The compiler itself remains compilable by FPC as part of bootstrap checks.
- PXX accepts a tested subset of Object Pascal with selected FPC-style syntax.
- PXX does not yet claim FPC RTL, package, object-file, unit-file, or full
  command-line compatibility.

See [Limitations](limitations.md) for the explicit gap list.
