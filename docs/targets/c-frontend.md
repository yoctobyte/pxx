---
title: C Frontend
order: 64
---

# C Frontend (`.c`)

PXX features a C frontend that compiles C source files directly to native ELF executables in a single pass. There is no separate assembly or linkage step. The compiler handles preprocessing, syntax parsing, type-checking, IR lowering, and machine code generation, producing a self-contained binary.

> [!NOTE]
> The C frontend is an alternative frontend sharing the PXX compiler backend. It supports compiling substantial real-world programs (e.g., `tiny-regex`, `Lua`, and `SQLite`) directly from C source.

---

## Dialect and Language Features

The C frontend supports a modern C subset suitable for compiling standard systems code and libraries:

### Supported Syntax & Types
- **Data Types**: Supports standard primitives (`char`, `int`, `double`, etc.), pointers, multidimensional arrays, and `typedef` statements.
- **Structures & Unions**: Supports standard structures, bit-fields, and nested anonymous structures/unions.
- **Functions**: Fully supports function prototypes, local function declarations, and function pointers (as local variables, struct members, and function return types, including typecast calls).
- **Varargs**: Supports `va_list` and `va_arg` for variable argument list handling.
- **Static Variables**: Supports local `static` variables and `static const` array/record initializations.

### Preprocessor Support
PXX includes an integrated preprocessor that handles:
- `#include` (including default CRTL search paths).
- `#define` and `#undef` macro definitions.
- Conditional compilation (`#if`, `#ifdef`, `#ifndef`, `#else`, `#elif`, `#endif`) with full preprocessor constant arithmetic evaluation.

---

## The "Magic Link" Model (Libc-Free Runtime)

To allow C programs to compile into compact, self-contained binaries, PXX provides its own C runtime library (CRTL) in `lib/crtl/` and uses an automated linking mechanism known as the **Magic Link**:

1. **Header Inclusion**: When a C program includes a standard header (such as `#include <math.h>`), the preprocessor maps this to `lib/crtl/include/math.h`.
2. **Auto-Pulling Implementation**: Immediately after loading the declarations, the preprocessor automatically pulls the corresponding implementation file from `lib/crtl/src/math.c`.
3. **Unity Compilation**: Symbol definitions from the `.c` implementations are compiled directly with the program. Undesired/unused symbols are discarded during dead-code elimination, resulting in a **libc-free, zero-dependency (`zero DT_NEEDED`)** binary.
4. **Deduplication**: Implementations are pulled at most once per compilation, preventing duplicate symbol definition conflicts and handling recursive includes.

---

## System Libraries Opt-Out

If a C program requires the host's actual libraries (e.g., standard `glibc` or `libm`) instead of PXX's bundled runtime, you can configure linking behavior using command-line options.

### 1. Global Opt-Out (`--system-libs`)
Using the `--system-libs` option tells the compiler to disable the magic-link auto-pull mechanism for all standard libraries. Declarations in `<header.h>` then map to external symbols, and the compiler emits standard `DT_NEEDED` metadata pointing to the host's shared libraries (e.g., `libc.so.6`, `libm.so.6`).

### 2. Granular Opt-Out (`--system-libs=<list>`)
You can specify a comma-separated list of soname stems (e.g., `--system-libs=m` or `--system-libs=m,pthread`) to opt out of the magic link only for specific libraries:
- Matching libraries (such as `libm` when `m` is specified) will bind to the host's real shared library.
- Other headers (like `<stdio.h>` and `<string.h>`) will continue to use the bundled, libc-free Magic Link implementations.

```sh
# Compile using system math library but magic-linked string/stdio
./pxx --system-libs=m program.c program
```

### 3. Integration Libraries Default
Libraries that PXX does not emulate (such as GTK, zlib, sqlite, pthread, and dl) are modeled as system libraries by default. Symbols imported from these headers will resolve via `DT_NEEDED` to the host system libraries unless explicit wrappers are configured.

---

## Next

- [Cross Languages](./cross-languages.md)
- [Nil Python](./nil-python.md)
- [Command Line Reference](../reference/cli.md)
