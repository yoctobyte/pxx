# Command Line

The compiler executable is `./compiler/pascal26`.

```sh
./compiler/pascal26 [options] source [output]
```

```sh
./compiler/pascal26 test/hello.pas /tmp/hello
/tmp/hello
```

With an output path, PXX writes an ELF executable there plus `<output>.map`.
Without one, it strips the input extension and refuses to overwrite the source.

## Frontend by suffix

| Suffix | Frontend |
| --- | --- |
| `.pas`, `.pp` (default) | Pascal |
| `.c` | C subset |
| `.bas` | BASIC (experimental) |

## Options

Options come before the source path.

| Option | Effect |
| --- | --- |
| `--debug` | Print lexer/parser/preprocessor diagnostics. |
| `--dump-ir` | Print lowered IR while still emitting the executable. |
| `--dump-rtti` | Print generated RTTI tables while still emitting the executable. |
| `-dNAME` / `-uNAME` | Define / undefine a conditional symbol (`PXX` cannot be undefined). |
| `-Mobjfpc` | Accept the Object Pascal mode marker (no semantic change). |
| `--strict-overload` / `--permissive-overload` | Require / relax `overload;` on overloaded routines. |
| `--threadsafe` | Atomic refcounts for managed strings/arrays. |
| `--no-auto-var` / `--no-lazy-var` | Disable auto-typed / inline `var` declarations (both on by default). See [Dialect](dialect.md). |
| `--no-unhandled-handler` | Exit status 1 silently on an unhandled exception. |
| `--experimental-ir-codegen` | Deprecated no-op; IR is the only backend. |

## Build commands (repo root)

| Command | Effect |
| --- | --- |
| `make` | Rebuild PXX from the checked-in seed; require byte-identical fixedpoint. |
| `make test` | Regression + FPC comparison + fixedpoint checks. |
| `make bootstrap` | Recovery: build a seed with FPC, then require fixedpoint. |
| `make fpc-check` | Verify an FPC-built compiler reproduces the current binary. |
