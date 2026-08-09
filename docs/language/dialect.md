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
- `.c` and `.npy` inputs route to the C and Nil Python frontends, which are
  mainline and gated alongside Pascal; `.bas` and `.rs` route to the
  experimental BASIC, Rust and Zig research frontends.

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

## Routine directives

Calling conventions are not the only decorators, and the rest are not uniformly
inert either. A directive here falls into one of three groups, and it is worth
knowing which — an inert one is free to write, a load-bearing one changes what
is compiled, and a rejected one stops the build.

### Load-bearing

These change the routine. Several refuse to compile when they cannot be honored,
which is deliberate: silently ignoring them would produce a working build that
does the wrong thing.

| directive | effect |
| --- | --- |
| `assembler` | the body is inline assembly; an ordinary `begin` body is an error |
| `generator` | the routine becomes a generator, and must be a function (its result type is the yielded element type) |
| `async` | asynchronous routine |
| `stackless` | selects the stackless strategy for an async routine |
| `interrupt` | raw hardware-vector ISR. Implemented for riscv32 (ESP32-C3) and xtensa Call0 (ESP32-S3) only; on any other target it is an **error**, naming `iram` as the alternative for an IDF-registered ISR |
| `flexcolumn` | call arguments accept `write`-style `:width[:decimals]` modifiers |
| `external` | the routine is a dynamically-linked import |
| `virtual`, `override`, `dynamic`, `abstract` | method dispatch (on a class member declaration) |
| `static` | on a **class method** declaration: no `Self` |

### Accepted and ignored

Written for the reader, or for FPC source compatibility. They parse and do
nothing.

| directive | why it is inert |
| --- | --- |
| `cdecl`, `register` | the calling convention is the target's — see above. `cdecl` on a *procedural type* is the exception |
| `inline` | the optimizer decides. At `-O2` it inlines any routine that qualifies (a function, scalar result, at most six scalar by-value parameters, not external or a generator) whether or not you wrote `inline`, and never inlines one that does not qualify because you did |
| `stackful` | the default async strategy; accepted so it can be stated explicitly |
| `static`, `reintroduce` | on a plain routine (`static` *is* meaningful on a class method) |
| `iram` | on targets other than xtensa and riscv32, where there is no IRAM to place anything in |
| `deprecated`, `platform`, `experimental`, `unimplemented`, `library` | hint directives — see [FPC compatibility](./fpc-compatibility.md#hint-directives). No usage warning is emitted yet |

`overload` is a case of its own: **inert by default**, required under
`--strict-overload`. PXX resolves overloads without it; the flag makes the
missing directive an error, the way FPC has it.

### Not accepted

`stdcall`, `safecall`, `pascal` and `mwpascal` parse only on a *method*
declaration — on a plain routine, an `external`, or a procedural type they are a
parse error. `varargs` is not accepted at all. These are gaps rather than
decisions; FPC sources using them need the directive removed.

### On unfulfillable directives

PXX does not currently warn when a directive is accepted but cannot be honored —
`iram` on x86-64 compiles silently. Only `interrupt` errors. A uniform
"this directive is ignored here" diagnostic is a known gap.

## Source compatibility posture

Prefer ordinary Object Pascal where possible. Use `{$ifdef PXX}` only for code
that intentionally depends on PXX behavior.

Do not use `{$ifdef FPC}` to mean "Object Pascal compiler". PXX does not define
`FPC`; that symbol belongs to Free Pascal.

## Next

- [FPC compatibility](./fpc-compatibility.md)
- [Command-line reference](../reference/cli.md)
