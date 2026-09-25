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

The C frontend targets a C99-class dialect (`__STDC_VERSION__` is `199901L`)
suitable for compiling standard systems code and libraries — it is the
frontend that passes all 220 programs of the **c-testsuite** conformance
battery and compiles real programs such as SQLite, Lua, zlib, cJSON and
QuickJS (see
[compatibility status](../reference/status.md)).

### Supported Syntax & Types
- **Data Types**: Standard primitives (`char`, `int`, `double`, etc.), the
  `stdint.h` fixed-width family, pointers, multidimensional arrays, and
  `typedef`.
- **Structures & Unions**: Standard structures, bit-fields (including wide
  bit-fields that span past 32 bits), and nested anonymous structs/unions.
  `#pragma pack(N)` / `push` / `pop` and `__attribute__((packed))` /
  `__attribute__((aligned(N)))` are honored — a packed `struct { char a; int b; }`
  really does report `sizeof == 5`, not 8.
- **Functions**: Function prototypes, local function declarations, function
  pointers (as locals, struct members, and return types, including typecast
  calls), and `inline`/`__inline__` (accepted; treated as a hint, not a hard
  requirement to inline).
- **Varargs**: `va_list` / `va_arg` for variable argument handling.
- **Static Variables**: Local `static` variables and `static const`
  array/record initializations.
- **C99/C11 constructs**: ternary, `goto`/labels, `switch`/`case`/`default`,
  compound literals (`(struct P){.x = 1, .y = 2}`), designated initializers,
  `restrict`/`__restrict__` (accepted, treated as a no-op — no aliasing
  optimization is derived from it), and `_Generic` selection expressions.
- **`setjmp`/`longjmp`**: implemented as compiler intrinsics rather than CRTL
  C code.

### Preprocessor Support
PXX includes an integrated preprocessor that handles:
- `#include` (including default CRTL search paths), `-I` (add an include
  directory), `-nostdinc` / `--nostdinc` (drop the default CRTL include path).
- `#define` / `#undef`, plus `-D name[=value]` / `-U name` on the command
  line.
- Conditional compilation (`#if`, `#ifdef`, `#ifndef`, `#else`, `#elif`,
  `#endif`) with full preprocessor constant arithmetic evaluation.
- Stringification (`#`), token pasting (`##`, with correct macro rescan), and
  variadic macros (`__VA_ARGS__`).
- `#pragma`, including `pack` and a push/pop macro stack.
- `--dump-cpp` prints the fully preprocessed translation unit instead of
  compiling it — useful for debugging macro expansion.

`#error` on an active branch stops the build with its message and a nonzero
exit code; `#warning` prints its message and the build continues.

### Not (yet) supported
No computed `goto`, no `_Complex` /
`_Atomic` / `<stdatomic.h>`, no C11 `<threads.h>`, and no vector-extension
intrinsics.

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
A header that `lib/crtl` does not provide, such as `zlib.h`, `sqlite3.h` or
GTK's, is read from the host's `/usr/include`, and the compiler warns that it
did so. Each function it declares is imported from the library that defines
it on your machine (`libz.so.1` for `zlib.h`), so the program links and runs.
A function the header's library does not export stays with libc. This is so
from pin v425; v424 imported every such function from `libc.so.6`, and the
program failed when started with `undefined symbol`. See
[Getting started with C](../getting-started/c.md#using-the-hosts-c-library-instead).

---

## CRTL Header Coverage

`lib/crtl/` bundles both the headers (`lib/crtl/include/`) and libc-free
implementations (`lib/crtl/src/`) that back the Magic Link. Implemented, with
a real `.c` body behind the header (not just declarations): `assert.h`,
`ctype.h`, `fcntl.h`, `locale.h`, `math.h` (the largest),
`pthread.h` (a real but partial threading subset — see below), `signal.h`,
`stdio.h` (the second largest), `stdlib.h`, `string.h`, `time.h`, `unistd.h`, and
socket-related headers. `setjmp.h` is backed by compiler intrinsics rather
than a `.c` file. `wchar.h` and `wctype.h` are partly implemented: `wcslen`,
`iswupper` and `towupper` work, while `wcscpy`, for example, is not declared.

`pthread.h` is a genuine subset, not a glibc-ABI-compatible implementation:
mutexes, `pthread_self`/`pthread_equal`, create/join, `pthread_once`, and
condition variables — no TLS keys, no thread cancellation, no scheduler
attributes. Threaded C code needs `--threadsafe`.

---

## Known Limitations

- **A C call to an undeclared/extern function binds case-insensitively across
  the C *and* Pascal namespace**, with no arity check. This is deliberate and
  is how a C corpus gets a math library at all (`sqrt`/`sin`/`cos` bind to the
  RTL's Pascal `Sqrt`/`Sin`/`Cos`) — but when a C name collides with an
  unrelated Pascal routine of a different signature, the call still compiles
  and fails at runtime instead of at compile time (a real example: C's
  `time(NULL)` binding to `sysutils`' zero-argument `Time: TDateTime`). If a
  C program behaves strangely right after adding a `uses`/library that pulls
  in more Pascal RTL surface, suspect a name collision first.
- **`-g` on a `.c` file currently reports line numbers from the fully
  preprocessed/macro-expanded buffer**, not the original source — stepping and
  breakpoints work, but the reported line can be wrong once macros or
  `#include` are involved.
- Very large single-translation-unit files (a multi-hundred-thousand-line
  amalgamation such as `sqlite3.c`) compile correctly but with mildly
  superlinear parse/codegen scaling — expect it to be slow, not wrong.

---

## Next

- [Cross Languages](./cross-languages.md)
- [Nil Python](./nil-python.md)
- [Command Line Reference](../reference/cli.md)
