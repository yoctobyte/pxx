# Command Line

The current compiler executable is `./compiler/pascal26`. `PXX` is the
provisional name used for compiler identity in source code; renaming the
binary and stable bootstrap artifacts is intentionally deferred.

## Compile A File

```sh
./compiler/pascal26 [options] source [output]
```

Examples:

```sh
./compiler/pascal26 test/hello.pas /tmp/hello
/tmp/hello

./compiler/pascal26 test/hello.c /tmp/hello-c
./compiler/pascal26 test/test_basic_lexer.bas /tmp/example-basic
```

If an output path is supplied, PXX writes an executable ELF file there and
also writes `<output>.map`, containing addresses for `_start` and generated
procedures/methods.

An explicit output path is recommended. The native PXX default is currently
the input path; the FPC-built bootstrap host uses FPC filename handling. That
default-output discrepancy is an implementation detail, not a stable CLI
promise.

## Input Selection

Frontend selection is filename-based:

| Source suffix | Frontend |
| --- | --- |
| `.pas`, `.pp`, or other non-special suffix | Pascal |
| `.c` | Supported C subset |
| `.bas` | BASIC frontend |

Pascal sources may additionally load supported Pascal units, local C source,
or C headers through `uses`; see [Features](features.md) and
[C Interoperability](../C_INTEROP.md).

## Compiler Options

Options must occur before the source path.

| Option | Behavior |
| --- | --- |
| `--debug` | Print compiler lexer/parser/preprocessor diagnostics while compiling. |
| `--legacy-codegen` | Opt back into the frozen direct AST→x86-64 emitter (reference only). The IR backend is the default since 2026-05-29; new features land in IR only and the legacy path cannot compile the newest ones (e.g. RTTI). |
| `--experimental-ir-codegen` | Deprecated no-op, accepted for compatibility. IR is already the default. |
| `--dump-ir` | Print the AST-lowered IR while still emitting the normal executable. |
| `-dNAME` | Define a Pascal conditional-compilation symbol. |
| `-uNAME` | Undefine a Pascal conditional-compilation symbol, except built-in `PXX`. |
| `-Mobjfpc` | Accept the current Object Pascal compatibility mode marker. It does not define `FPC` or change semantics yet. |
| `--strict-overload` | Require `overload;` on every variant when a routine name is overloaded. |
| `--permissive-overload` | Restore the default permissive overload behavior after an earlier strict option. |
| `--no-unhandled-handler` | Exit with status 1 silently for an unhandled Phase 1 exception. |
| `-fno-unhandled-handler` | Alias for `--no-unhandled-handler`. |

Example:

```sh
./compiler/pascal26 -Mobjfpc -dLOGGING --strict-overload app.pas /tmp/app
```

In Pascal code:

```pascal
{$ifdef LOGGING}
  writeln('logging enabled');
{$endif}
```

## Build Commands

Run from the repository root:

| Command | Behavior |
| --- | --- |
| `make` | Rebuild PXX using the checked-in self-hosted seed and require a fixedpoint. |
| `make test` | Run regression coverage, FPC comparison, and self-hosted fixedpoint checks. |
| `make bootstrap` | Recovery path: compile a seed with FPC, then require the PXX fixedpoint before installing it. |
| `make fpc-check` | Check that an FPC-built compiler produces the same current PXX binary. |
| `make benchmark` | Benchmark self-compilation and Hello World compilation; requires `hyperfine`. |
| `make stabilize` | Run tests and record a stable binary generation. |

FPC is a bootstrap/recovery and verification host. PXX programs are not
therefore entitled to assume the FPC RTL, FPC object ABI, or FPC compiler
identity.
