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

## Inline and auto-typed variables

PXX introduces two modern conveniences to the Pascal language surface, both of which are **enabled by default**:

1. **Inline variables**: You can declare a variable using the `var` keyword anywhere inside a `begin ... end` block, rather than only in a routine's top-level `var` section. Inline variables are scoped to the block in which they are declared.
2. **Auto-typed variables**: If a variable declaration includes an initializer, the compiler can automatically infer its type. You can either omit the type entirely or use the `auto` keyword.

For example:

```pascal
begin
  var i := 0;              { inferred Integer, declared inline }
  var name: auto := 'PXX'; { explicit auto keyword }
  var x: Double := 3.14;   { inline, explicit type }
  
  for i := 1 to 10 do
    writeln(name, ' count: ', i);
end;
```

These features can be disabled by passing `--no-auto-var` and `--no-lazy-var` (or `-fno-auto-var` and `-fno-lazy-var`) to the compiler.

## Source compatibility posture

Prefer ordinary Object Pascal where possible. Use `{$ifdef PXX}` only for code
that intentionally depends on PXX behavior.

Do not use `{$ifdef FPC}` to mean "Object Pascal compiler". PXX does not define
`FPC`; that symbol belongs to Free Pascal.

## Next

- [FPC compatibility](./fpc-compatibility.md)
- [Command-line reference](../reference/cli.md)
