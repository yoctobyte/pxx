# C Interoperability

Frankonpiler can import C headers and link against shared C libraries, or
compile C source files directly into Pascal programs.

## Direct Pascal `external` Binding

A Pascal routine can bind a shared-library symbol directly, without going
through a C header. This is the right tool when the real headers are not
practical to import (for example GTK, whose headers pull in large macro
trees):

```pascal
function gtk_get_major_version: Integer; cdecl; external 'libgtk-3.so.0';
procedure gtk_init(argc: Pointer; argv: Pointer); cdecl; external 'libgtk-3.so.0';
```

The soname after `external` is recorded as a `DT_NEEDED` entry; calls use the
same PLT/GOT dynamic-link path as header-imported externals (System V AMD64 /
`cdecl`). The link symbol defaults to the routine name (GTK symbols are valid
lowercase identifiers); an optional `name 'symbol'` clause overrides it.

A hand-written binding unit is just a list of such declarations — see
`test/gui/gtk3.pas` and [GUI](docs/gui.md).

## Calling A Shared C Library

Pascal source imports a supported C header through `uses` and calls an
external function directly:

```pascal
program test_shared_object;
uses ctype;
begin
  writeln(tolower(65));
end.
```

Build and run the included regression:

```sh
./compiler/pascal26 test/test_shared_object.pas /tmp/test_shared_object
/tmp/test_shared_object
```

Output:

```text
97
```

For this example, `uses ctype;` resolves to the installed C header:

```text
/usr/include/ctype.h
```

On Linux the required shared object is `libc.so.6`. The generated executable
records the soname; it does not bake in the filesystem path.

## Unit Resolution Order

For a unit named `name`, the compiler searches in this order:

```text
<source directory>/name.pas
<source directory>/name.pp
<source directory>/name.c
<source directory>/name.h
compiler/name.pas
compiler/name.pp
compiler/name.c
compiler/name.h
/usr/include/name.h
```

If a `.c` file is found, supported function definitions are compiled into the
program directly (`uses my_c_lib;` — see `test/test_c_import.pas`).

If a `.h` file is found, supported function prototypes become external calls.
Only functions actually called by the Pascal program are emitted into the
dynamic symbol and relocation tables. The ELF writer adds the dynamic loader
metadata to resolve those calls at startup.

`ctype` is explicitly mapped to `libc.so.6`. Other header unit names default
to `lib<name>.so`; additional system library naming rules will be added as
more APIs are exercised.

## C Preprocessor Support

A preprocessing phase rewrites imported C input before lexing. Supported features:

- Comment removal, continued directive lines
- `#include`, common include guards (searches base directory, `/usr/include`, `/usr/include/x86_64-linux-gnu`, `/usr/lib/gcc/x86_64-linux-gnu/13/include`, `/usr/lib/llvm-18/lib/clang/18/include`)
- `#define` / `#undef`
- `#if` / `#ifdef` / `#ifndef` / `#elif` / `#else` / `#endif`
- Object-like macros and parameter substitution for function-like macros
- **Fully recursive macro expansion and rescan** with standard paint-blue logic to prevent infinite self-reference recursion.
- **GCC attribute and qualifier discarding**: Discards `__attribute__((...))`, GObject annotations (`G_GNUC_*`), GLIBC macros, and other compiler-specific specifiers/qualifiers to prevent poisoning parser inputs.

Not yet supported: token pasting (`##`), stringification (`#`), variadic macros, complex callbacks, variadic functions, full pointer marshalling.

## Struct & Record Alignment and Packing

Frankonpiler supports binary-compatible struct mapping for C interoperability through Pascal packed and aligned records:

- **Packed Records**: Declaring a record as `packed record` forces all field alignments to 1 (no padding bytes).
- **Directives Support**: Dynamic `$PACKRECORDS N` and `$ALIGN N` directives (where `N` can be `1`, `2`, `4`, `8`, `16`, `default`, or `normal`) change the packing alignment threshold dynamically inside the source file. The compiler uses a per-token historical tracking array (`TokPackRecords`) to preserve the correct alignment context active at the time of each token's lexing.
- **Nested Record Layout**: Propagates computed alignments of nested structures dynamically (`UClsAlign`), allowing naturally aligned outer records to embed packed inner structures correctly.

## Scope Limitations

This is an early interop surface, not a complete C ABI or header frontend.
It handles simple function prototypes with integer and character-like
arguments and return values. It tolerates unsupported declarations in system
headers so that usable simple prototypes can still be found.

### Suggested: lazy casing for C imports

C-imported symbols currently require exact case because their link names are
exact. A deferred compatibility feature is `{$LAZYCASING ON}` for C imports
only, default off. It would keep exact lookup first, then accept a
case-insensitive fallback only when exactly one imported C symbol matches,
while preserving the declaration's exact spelling for ELF linkage. Ambiguous
matches would remain errors. This should be implemented only after warnings
exist so accepted misspellings remain visible.

## Compiler Tracing

Use `--debug` to see C preprocessing events (selected includes, macro
definitions, active conditional branches, expansions):

```sh
./compiler/pascal26 --debug test/test_c_preprocess.pas /tmp/out
```

## Regression Coverage

`make test` covers all three C paths:

- `test/test_shared_object.pas` — imports `/usr/include/ctype.h`, loads
  `tolower` from `libc.so.6`, expects `97`.
- `test/test_c_import.pas` — compiles a local `.c` definition, expects `42`.
- `test/test_c_preprocess.pas` — exercises includes, guards, conditionals,
  and function-like macro substitution, expects `42`.
