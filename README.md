# PXX (provisional)

A self-hosting Pascal compiler that emits x86-64 Linux ELF executables
directly — no assembler, no linker, no external libraries required.

`PXX` is the working name and compiler identity while naming is still open.
The existing executable remains `compiler/pascal26` until that rename is
worth carrying through bootstrap/stable artifacts.

The compiler itself is written in plain standard Pascal (no OOP). It compiles
Object Pascal: classes, inheritance, generics (both class generics and generic
functions), routine and operator overloading, loop control, and more. The goal is a
Pascal superset / dialect that extends the language where it makes sense.

Focus: Linux / POSIX. Single target for now: x86-64.

## Highlights

- **Self-hosting** — the compiler compiles itself. No external toolchain
  needed at runtime.
- **Tiny output** — a Hello World binary is 325 bytes. No runtime, no stdlib
  linked in.
- **Generic functions** — `generic function Max<T>` + `specialize Max<Integer>
  as MaxInt` — and class generics.
- **Overloading** — routine dispatch with optional `overload;`, plus class
  operator implementations such as `operator +(a, b: TPoint): TPoint`.
- **Conditional compilation** — `{$ifdef PXX}`, user `{$define}`/`{$undef}`,
  nesting, and command-line `-dNAME` definitions without claiming `FPC`
  identity.
- **Compatibility switches** — opt-in `{$strict_overload on}` or
  `--strict-overload` enforces explicit routine overload declarations.
- **C interop** — `uses ctype;` imports a C header; the compiler reads it,
  links the shared object. See [C_INTEROP.md](C_INTEROP.md).
- **Fast** — compiles itself in ~68 ms. FPC takes ~600 ms on the same source.

## Build

Normal rebuild uses the checked-in self-hosted seed:

```sh
make        # rebuild compiler from itself
make test   # full regression suite + fixedpoint check
```

## Bootstrap

The recovery path uses Free Pascal (FPC) to rebuild the seed from scratch:

```sh
make bootstrap
```

Other standard Pascal compilers should work in place of FPC. After bootstrap,
the compiler is fully self-hosting again: the new seed must compile itself
to a fixedpoint (gen1 == gen2) before the build is accepted.

The goal is that `make bootstrap` becomes increasingly rare. Any regression
that requires it is noted in `compiler/usernotes.md`.

## Debug Tracing

```sh
./compiler/pascal26 --debug source.pas /tmp/out
```

Reports lexer/parser diagnostics and C preprocessing events.

## Project Notes

Design decisions, dialect proposals, and bootstrap history live in
`compiler/usernotes.md`. Current FPC-compatibility claims and missing-language
inventory are tracked in [COMPATIBILITY.md](COMPATIBILITY.md).
