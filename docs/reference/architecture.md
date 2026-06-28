---
title: Compiler architecture
order: 91
---

# Compiler architecture

PXX is a from-scratch, self-hosting native compiler. It functions as its own assembler and linker, emitting final Linux ELF executables directly with no external toolchain dependencies.

## The Compiler Pipeline

The compiler processes source code through a direct, single-pass pipeline:

```
Source File (.pas / .npy) 
    │
    ▼
Lexer (Token Stream)
    │
    ▼
Parser (AST / Abstract Syntax Tree)
    │
    ▼
Intermediate Representation (Linear IR)
    │
    ▼
Codegen (Machine Code / x86-64 / Target Bytes)
    │
    ▼
ELF Writer (Final Executable)
```

### 1. Language Frontends
PXX is primarily an Object Pascal compiler, but it uses a modular frontend architecture. The compiler dispatches parsing based on the source file extension:
- **Pascal (`.pas`, `.pp`)**: The main, fully-featured Object Pascal dialect.
- **Nil Python (`.npy`)**: A statically compiled Python-like dialect with local type inference.
- **C (`.c`)**: An alternative frontend compiling C source directly to native executables via a libc-free runtime.
- **BASIC (`.bas`)**: An experimental frontend used to test backend reuse.

### 2. Lexer
The lexer converts raw source text into a flat stream of tokens. 
- In the Pascal frontend, the lexer handles standard Pascal symbols, comments, and directives.
- In the Nil Python frontend, the lexer is **indentation-aware**. It tracks indentation levels using an internal stack to emit synthetic `INDENT` and `DEDENT` tokens. It also tracks parenthesis depth (`(`, `[`, `{`), suspending indentation rules when inside open parentheses to allow flexible multi-line formatting.

### 3. Parser
The parser processes the token stream to verify syntax and build the Abstract Syntax Tree (AST). Frontends share common expression-parsing and type-checking routines where their semantics overlap, ensuring consistent type safety across dialects.

### 4. Abstract Syntax Tree (AST)
The AST represents the parsed program structure as a tree of nodes (e.g., binary operations, routine calls, class instantiations, and variable references). 

### 5. Intermediate Representation (IR)
The compiler lowers the AST into a linear Intermediate Representation (IR). The linear IR simplifies control flow and prepares operations for target-specific code generation. 

### 6. Target Codegen & ELF Writer
The backend translates the linear IR into target machine bytes and writes the final ELF binary.
- **Static Binaries**: For programs using pure system calls without external libraries, PXX writes a single load segment with no dynamic section.
- **Dynamic Binaries**: When external C libraries are imported, the compiler automatically emits dynamic ELF metadata (`PT_INTERP`, `PT_DYNAMIC`, `DT_NEEDED`, GOT, and PLT-style indirect calls).

Supported target architectures:
- **`x86_64`**: Native Linux ELF output (default).
- **`i386`**, **`aarch64`**, **`arm32`**: Linux cross-compilation targets.
- **`riscv32`**, **`xtensa`**: Embedded/bare-metal targets oriented around ESP32 hardware.

---

## Platform Abstraction Layer (PAL)

The Platform Abstraction Layer (PAL) is the low-level capability abstraction layer (`lib/rtl/platform.pas`) that acts as the porting seam for the runtime library. It separates platform-independent RTL units (such as `sysutils`, `classes`, and `http`) from OS-specific or hardware-specific implementations.

Higher-level libraries query capabilities or handle errors portable-style (e.g., checking `PalHasSockets` or catching `PAL_ERR_UNSUPPORTED`) instead of using platform-specific conditional compilation.

### Backends

1. **`posix` (Hosted Linux)**:
   - Implements file handle operations and IPv4 TCP sockets.
   - Uses raw Linux system calls directly (libc-free by default).
2. **`esp` (ESP-IDF/FreeRTOS)**:
   - Implements file handles backed by ESP-IDF newlib stdio.
   - Implements sockets backed by lwIP BSD-socket calls.
   - Maps scheduler hooks to FreeRTOS task delays and hardware timers.

---

## Nil Python & C Interop (Autotyping)

The Nil Python frontend (`.npy`) compiles directly to the same native backend as Pascal. It has direct, wrapper-free access to system C libraries via the compiler's unified interop machinery.

For example, a Nil Python program can import the system SQLite header and call it directly without any handwritten Pascal or C glue code:

```python
import sqlite3

db = sqlite3_open("/tmp/test.db")
sqlite3_exec(db, "CREATE TABLE t(id INTEGER, name TEXT);", 0, 0, 0)
```

### The Autotyping (Return-Lifting) Feature

C APIs often return status codes and pass output handles via pointer-to-pointer parameters, such as:

```c
int sqlite3_open(const char *filename, sqlite3 **ppDb);
```

Since Nil Python does not expose raw pointers or address-of (`&`) operators, the compiler automatically resolves this mismatch using **autotyping / return-lifting**:

1. **Detection**: When importing a C header, the compiler analyzes the parameter signatures. If a function ends with a double-pointer out-parameter (`T**`), it flags the routine for return-lifting.
2. **Allocation**: When the function is called (e.g., `db = sqlite3_open(path)`), the compiler automatically allocates a hidden local pointer variable on the stack.
3. **Invocation**: The compiler generates code that passes the address of this hidden pointer to the C function.
4. **Lifting**: The compiler intercepts the C function's normal return value and instead "lifts" the value of the hidden pointer (the allocated handle) as the Python-level return value of the call.

### Additional Interop Mechanisms

- **String Marshalling**: Python strings passed to C pointer parameters (`const char*`) are automatically marshalled as NUL-terminated C strings.
- **String Return Conversion**: Returned C `char*` pointers are automatically copied into managed, reference-counted PXX strings. The underlying C memory remains owned by the C library.
- **Constant Mapping**: C preprocessor integer `#define` macros (e.g., `SQLITE_ROW`) are parsed and mapped directly to ordinary compiler constants.
- **Callback Collapsing**: C function-pointer parameters collapse to a generic `Pointer`, allowing programs to pass `0` when no callback is required.
