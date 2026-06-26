---
title: PXX dialect
order: 44
---

# PXX dialect

PXX is an Object Pascal dialect. It deliberately follows FPC behavior for many
implemented features, but it is not a full FPC clone and it also has
PXX-specific extensions.

## Common supported surface

PXX supports a tested Object Pascal subset including:

- programs and units
- constants, variables, records, arrays, sets, and strings
- procedures, functions, `var`/`const`/`out` parameters, overloads, and operators
- classes, inheritance, virtual dispatch, constructors, properties, and RTTI
- interfaces, `is`/`as`, exceptions, and generics
- conditional compilation with `{$ifdef}`, `{$ifndef}`, `{$if}`, `{$else}`,
  `{$elseif}`, and `{$endif}`

## PXX-specific or early surface

Some features are project-specific or still early:

- `PXX` is predefined when compiling Pascal input.
- `-dNAME` and `-uNAME` define and undefine conditional symbols.
- `--threadsafe` enables atomic reference counts for managed strings and arrays.
- `--no-auto-var` and `--no-lazy-var` disable PXX's auto-typed/inline variable
  declarations.
- `--target=ARCH` selects the output CPU target.
- `.c`, `.bas`, and `.npy` inputs route to experimental non-Pascal frontends.

## Source compatibility posture

Prefer ordinary Object Pascal where possible. Use `{$ifdef PXX}` only for code
that intentionally depends on PXX behavior.

Do not use `{$ifdef FPC}` to mean "Object Pascal compiler". PXX does not define
`FPC`; that symbol belongs to Free Pascal.

## Next

- [FPC compatibility](./fpc-compatibility.md)
- [Command-line reference](../reference/cli.md)
