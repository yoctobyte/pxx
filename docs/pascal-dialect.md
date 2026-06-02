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

{$if defined(FEATURE) and not defined(DISABLED)}
  writeln('expression enabled');
{$elseif 1}
  writeln('fallback');
{$endif}
```

Symbols and directive names are case-insensitive. Blocks may be nested.
`PXX` is a built-in identity symbol and cannot be undefined from source or
with `-uPXX`. The expression subset supports `defined(NAME)`, bare symbols,
`not`, `and`, `or`, parentheses, `0`, and `1`. `{$warning text}`,
`{$message text}`, and `{$error text}` act only in active branches. Include
directives are expanded only from active branches and remain one level deep.

Not yet implemented: valued defines, macro replacement, or general FPC
switch-state behavior.

## Comments

Three comment forms are recognised: brace `{ ... }`, paren-star `(* ... *)`,
and line `// ...`. A `(* ... *)` (or any) comment may be followed by code on
the same line.

Two opt-in switches relax comment handling (both default **off**, matching
Turbo Pascal / classic Delphi, which do not nest comments):

```pascal
{$NESTEDCOMMENTS ON}   { nest { } and (* *): an inner opener raises the depth }
{$CSTYLECOMMENTS ON}   { recognise C-style /* ... */ comments (non-nesting) }
```

With `NESTEDCOMMENTS` off, a brace comment ends at the first `}` and a
paren-star comment at the first `*)`. `CSTYLECOMMENTS` is a pure extension
(standard Pascal has no `/* */`); leaving it off keeps `/` adjacent to `*`
parsing as division. Both accept `ON`/`OFF` and are case-insensitive.

## Identifier Case Modes

Pascal identifiers are case-insensitive by default. `Min`, `min`, and `MIN`
resolve to the same Pascal declaration unless strict mode is enabled:

```pascal
{$CASESENSITIVE ON}
```

`{$CASESENSITIVE ON/OFF}` is case-insensitive and applies to declarations in
the current Pascal source context. The compiler source opts into strict mode to
catch misspellings during self-compilation.

Case is resolved **per symbol origin** rather than by lowercasing every name.
C-imported symbols stay case-sensitive because their link names are exact.
`docs/todo.md` records a deferred C-import-only `{$LAZYCASING}` compatibility
idea; it is not implemented and would not alter strict Pascal behavior.

## Tested Language Surface

The regression suite currently covers:

- Programs, Pascal units, and qualified `UnitName.Symbol` lookups.
- Constants, variables, integer, Boolean, character, and string operations.
- Arrays and records.
- Procedures, functions, `var` parameters, and overload dispatch.
- `if`, `case`, `while`, `for`, `repeat`, `break`, and `continue`.
- Classes with fields, methods, and named `class of` metaclass aliases.
- Generic classes and generic procedures/functions using explicit specialization.
- Operator implementations for class/record operands.
- Virtual/override method dispatch, including from procedure-call statements.
- Procedure and method references (`@routine`, `@obj.method`).
- Typed-pointer indexing, casts, fields, and scaled arithmetic.
- `PChar`/`PAnsiChar` pointer types and the `PChar(s)` cast, which marshals a
  Pascal string to a NUL-terminated C `const char*` (skips the inline length
  prefix); a `PChar` is indexable to read a returned C string.
- Published RTTI and binary form (`.lfm`) streaming into a component tree.
- Untyped `try/except`, `try/finally`, `raise <expr>`, and handler re-raise.
- Selected C imports and direct `external` shared-library binding.
- Heap: `GetMem`/`FreeMem` (free-list reuse), `New`/`Dispose`, `ReallocMem`.
- `Str(x[:w[:d]], s)` and `Val(s, n, code)` for integers, via an auto-included
  `builtin` unit (pulled in only when used).

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

Exception handling supports catch-all handlers, exact user-class typed
handlers, and finalizers:

```pascal
try
  raise 42;
except
  writeln('caught');
end;

try
  writeln('work');
finally
  writeln('cleanup');
end;

try
  raise TParseError.Create;
except
  on E: TParseError do writeln(E.Code);
end;
```

`except else` is also accepted as an explicit catch-all form. A raised
expression can cross procedure and unit boundaries, and `raise;` is accepted
inside a handler. `on E: TClass do` binds a raised object and matches its
declared user-class type exactly. Class inheritance, a built-in `Exception`
base/message constructor, inherited matches, and class/message diagnostics
are not implemented yet. `Exit`, `break`, and `continue` run finalizers and
remove handler frames only when their destination leaves protected code.

## Procedure And Method References

`@` takes the address of a routine or of a bound method:

```pascal
p := @SomeRoutine;        { Pointer to the routine's code }
m := @obj.Method;         { a TMethod (code + instance) — an `of object` value }
```

`@SomeRoutine` yields the routine's runtime code address as a `Pointer`,
suitable for passing to C callbacks (e.g. `g_signal_connect`, `qsort`).
`@obj.Method` yields a two-pointer `TMethod` (code address + the instance),
which is what an `of object` event such as `OnClick` stores. Taking the
address of an external routine is rejected (it has no link-time address);
wrap it in a local routine instead.

## Classes, Virtual Methods, And RTTI

Classes support fields, methods, single inheritance, virtual/override dispatch
(VMT), properties with field or method accessors, and class visibility sections
(`private`/`protected`/`public`/`published`). Each class's VMT is filled by
inheritance, so a subclass declared in a later unit correctly inherits an
ancestor's overrides.
Inside a constructor or method, `inherited Create(...)`, `inherited Method`,
and bare `inherited` call the matching ancestor implementation statically.

A class with a `published` section (in itself or an ancestor) gets a minimal,
custom RTTI table. The reflection API uses `System.TypInfo` names
(`GetClass`, `GetPropInfo`, `GetOrdProp`/`SetOrdProp`, `GetStrProp`/`SetStrProp`,
`GetMethodProp`/`SetMethodProp`, ...) covering streaming-grade property kinds:
ordinal, enum, set, string, class, and method (event). On top of this, a binary
form stream (`.lfm`) can instantiate and configure a component tree — see
[GUI](gui.md).

A bare method call inside another method binds statically; use `Self.Method`
for virtual dispatch on the current instance.

## Parameter Passing Notes

`const` record parameters are passed by reference (as in FPC); a by-value
record larger than a machine word would otherwise be truncated.

## Shared-Library Binding

A Pascal routine can bind a shared-library symbol directly:

```pascal
procedure gtk_init(argc, argv: Pointer); cdecl; external 'libgtk-3.so.0';
```

See [C Interoperability](../C_INTEROP.md).

## Compatibility Claim

PXX source compatibility should be stated narrowly:

- The compiler itself remains compilable by FPC as part of bootstrap checks.
- PXX accepts a tested subset of Object Pascal with selected FPC-style syntax.
- PXX does not yet claim FPC RTL, package, object-file, unit-file, or full
  command-line compatibility.

See [Limitations](limitations.md) for the explicit gap list.
