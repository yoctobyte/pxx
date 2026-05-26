# Frankonpiler Handover

**Date:** 2026-05-26

## Current Git State

Relevant commits on `master`:

```text
4e33759 feat(debug): add runtime compiler tracing
e7f8b2a docs: document shared C library loading
8fcc080 feat(elf): load external C functions
ce2da9a chore: checkpoint parser work in progress
```

`ce2da9a` deliberately preserves unfinished BASIC/AST parser and Pascal
class/method work before the shared-object track started. Do not interpret
that checkpoint as feature completion.

## Shared Object Loading: Working

The compiler can now compile a Pascal program that imports a simple installed
C header and calls a function supplied by a Linux shared object:

```pascal
program test_shared_object;
uses ctype;
begin
  writeln(tolower(65));
end.
```

The checked-in regression is `test/test_shared_object.pas`. On this system:

```text
header:  /usr/include/ctype.h
soname:  libc.so.6
result:  tolower(65) = 97
```

The generated executable is dynamically loadable ELF output with:

- `PT_INTERP` naming `/lib64/ld-linux-x86-64.so.2`
- `PT_DYNAMIC`
- `DT_NEEDED` for `libc.so.6`
- string, symbol, SysV hash, and `R_X86_64_GLOB_DAT` relocation data

Ordinary programs with no external calls remain in the prior static-style
single-load-segment format.

## Header And Library Resolution

`ParseUsesUnit` searches for `uses name;` as:

```text
<source dir>/name.pas, .pp, .c, .h
compiler/name.pas, .pp, .c, .h
/usr/include/name.h
```

For C input:

- A local `.c` function body is compiled into the executable.
- A `.h` prototype is registered as external and is dynamically resolved only
  if called.
- A later local definition clears external status, so a prototype followed by
  a definition continues to use the embedded implementation.
- `ctype` is specially mapped to `libc.so.6`.
- Other headers currently default to `lib<unit>.so`; add mappings as system
  library coverage expands.

The header parser is deliberately small. Simple prototypes such as
`int tolower(int)` work; full C header/ABI coverage does not yet exist.

## C Preprocessing

The compiler includes `compiler/cpreproc.inc`, a preprocessing stage run
before C lexing for direct `.c` inputs and imported `.c`/`.h` units. It
supports:

- comment removal and backslash-continued directive lines
- local and installed-header `#include`
- common include guards and conditional selection
- `#define`/`#undef`, object macros, and basic function-like parameter
  substitution

`test/test_c_preprocess.pas` exercises a local include, include guard,
conditional selection, undefinition, and function-like expansion; it now
returns `42` under the self-hosted compiler.

The implementation deliberately does not claim complete C preprocessing:
stringification, token pasting, variadic macros, and full rescanning remain
future work.

## Debug Tracing

`pascal26 --debug <src> [out]` now enables the existing lexer/parser traces
and new C-preprocessor event traces. This immediately diagnosed the
self-hosted preprocessor failure: passing local open arrays through
`CPExpandFunction` corrupted the expansion-level argument. Macro arguments
are now kept in depth-indexed fixed storage instead.

This is compiler tracing, not ELF symbolic debugging. Generated executables
still do not carry section-based debug symbols or DWARF data.

## Implementation Notes

Changed areas for the shared-object feature:

| File | Purpose |
|---|---|
| `compiler/parser.inc` | unit/header lookup, system header fallback, library mapping |
| `compiler/cparser.inc` | external prototype registration and local-body override |
| `compiler/cpreproc.inc` | rewrite C preprocessing constructs before C lexing |
| `compiler/clexer.inc` | tokenize rewritten C input |
| `compiler/symtab.inc` | emit indirect calls through external GOT-style slots |
| `compiler/elfwriter.inc` | emit dynamic ELF metadata and relocations |
| `compiler/defs.inc` | external/dynamic bookkeeping and large unit scratch buffer |
| `test/test_shared_object.pas` | installed `ctype.h` / `libc.so.6` regression |
| `test/my_c_lib.c` | local prototype plus definition regression |
| `test/test_c_preprocess.pas` | include/condition/macro preprocessing regression |

An important fix made during this work is `UnitContent`: imported source/header
contents are now loaded into a global string buffer. A local `AnsiString` in a
self-hosted generated procedure only has the small local-string capacity, so
reading the approximately 11 KB `/usr/include/ctype.h` into that local buffer
corrupted the stack.

## Verification

Passed after `8fcc080`:

```sh
make bootstrap
make fpc-check
make test
```

`make test` now checks:

- shared-object `ctype` import returns `97`
- local C import returns `42`
- normal Pascal regressions and recursive fixed-point self compilation

## Parked Workstreams

Two concurrent feature streams were intentionally checkpointed and left for
later resumption:

1. BASIC lexer/parser/AST work in `compiler/blexer.inc`,
   `compiler/bparser.inc`, and `test/test_basic_comprehensive.bas`.
2. Pascal classes/methods/interface parsing work in `compiler/parser.inc`,
   `compiler/defs.inc`, and related class tests.

The shared-object feature touched some common compiler modules, so a resumed
branch should start from current `master` rather than replaying older source
over the ELF/import changes.

Checked directly after the shared-object work, these parked tests currently
segfault the compiler during compilation (`SIGSEGV`, exit status 139):

```text
test/test_class.pas
test/test_class_methods.pas
test/test_basic_comprehensive.bas
```

They are not included in `make test` at this stage; this is expected unfinished
work, not a passing baseline. The class-method target source remains in
`test/test_class_methods.pas`, and the BASIC cross-language/import target is in
`test/test_basic_comprehensive.bas`.

## Suggested Next Interop Steps

1. Replace the hardcoded header-to-soname special case with explicit import
   syntax or a small mapping table.
2. Exercise another simple installed library header whose ABI fits the current
   parser, then add it to `make test`.
3. Grow C type handling only as demanded by real library calls: pointer
   arguments, buffers, typedef aliases, then structs/callbacks.
