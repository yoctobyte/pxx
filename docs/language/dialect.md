---
title: PXX dialect
order: 44
---

# PXX dialect

PXX is an Object Pascal dialect. It deliberately follows FPC behavior for many
implemented features, but it does not aim for full FPC compatibility and it
also has PXX-specific extensions.

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

## Calling conventions

A calling convention in PXX is a property of the **target**, not of a routine.
Each platform has exactly one, and the compiler uses it: the System V AMD64 ABI
on 64-bit Linux, the target's own C ABI when cross-compiling. There is no
per-routine choice to make.

So on a routine — a definition, a forward declaration, an `external`, or a
method — a convention directive is **decoration**. These compile to the same
code:

```pascal
function sq(x: Double): Double; external 'libm.so.6' name 'sqrt';
function sq(x: Double): Double; cdecl; external 'libm.so.6' name 'sqrt';
```

Both call the C function correctly. The second is not more correct, only more
explicit for a human reader: the call uses the platform C ABI because the
routine is `external`, not because `cdecl` is written.

Which spellings are *accepted* is uneven today, and worth knowing before you
port FPC sources:

| directive | on a routine or `external` | on a procedural type | on a method declaration |
| --- | --- | --- | --- |
| `cdecl` | accepted | **meaningful — see below** | accepted |
| `register` | accepted | rejected | accepted |
| `stdcall`, `safecall`, `pascal`, `mwpascal` | rejected | rejected | accepted |

A rejected directive is a parse error, not a warning, so FPC code that writes
`stdcall` on a plain routine will not compile as-is.

### The exception: `cdecl` on a procedural type

On a **procedural type** — a function-pointer type — `cdecl` is not decoration.
It marks the signature as C-ABI so that an *indirect* call through a value of
that type marshals its arguments the C way. Leave it off a pointer to a real C
function and the call is compiled with PXX's internal convention: it will build,
run, and produce a wrong answer.

```pascal
type
  TPlain = function(x: Double): Double;
  TCdecl = function(x: Double): Double; cdecl;
```

Given a `dlsym`'d pointer to a C `double dtwice(double)`, calling it through
`TPlain` yields `21.0` for an argument of `21.0` — the argument never reaches
the register the C function reads — while `TCdecl` yields the correct `42.0`.

The rule of thumb: **if you are writing a type for a pointer to a C function,
write `cdecl` on it.** Everywhere else the marker is documentation.

## Source compatibility posture

Prefer ordinary Object Pascal where possible. Use `{$ifdef PXX}` only for code
that intentionally depends on PXX behavior.

Do not use `{$ifdef FPC}` to mean "Object Pascal compiler". PXX does not define
`FPC`; that symbol belongs to Free Pascal.

## Next

- [FPC compatibility](./fpc-compatibility.md)
- [Command-line reference](../reference/cli.md)
