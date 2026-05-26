# Frankonpiler

Frankonpiler is a self-hosting Pascal compiler growing into a native,
multi-language compiler. It emits x86-64 Linux ELF executables directly,
without invoking an assembler or linker.

## Build And Test

Normal rebuilds use the checked-in self-hosted compiler seed:

```sh
make
make test
```

`make bootstrap` is the recovery path: it uses Free Pascal to build a seed,
then requires the self-hosted generations to reach the same fixed point.

## Calling A Shared C Library

Pascal source can import a supported C header through `uses` and call an
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

On the current Linux system, the required runtime shared object is available
as `libc.so.6` (resolved by the dynamic loader to a path such as
`/lib/x86_64-linux-gnu/libc.so.6`). The generated executable records the
soname `libc.so.6`; it does not bake in that filesystem path.

### How Resolution Works

For a unit named `name`, the compiler currently searches in this order:

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
program, as in `uses my_c_lib;` in `test/test_c_import.pas`.

If a `.h` file is found, supported function prototypes are external calls.
Only functions actually called by the Pascal program are emitted into the
dynamic symbol and relocation tables. The ELF writer then adds the dynamic
loader metadata required to resolve those calls at program startup.

`ctype` is currently mapped explicitly to `libc.so.6`. Other header unit names
default to a shared-object name of the form `lib<name>.so`; additional system
library naming rules will need to be added as more APIs are exercised.

### Current C Header Scope

This is intentionally an early interop surface, not a complete C ABI/header
frontend. It currently handles simple function prototypes using integer and
character-like arguments and return values, with basic pointer syntax skipped
where sufficient for declaration recognition. It tolerates unsupported
declarations in system headers so usable simple prototypes can still be
found.

Complex typedefs, structs, macros, callbacks, variadic functions, full pointer
marshalling, and arbitrary platform header layouts are not yet promised.

### Regression Coverage

`make test` covers both C paths:

- `test/test_shared_object.pas`: imports `/usr/include/ctype.h`, loads
  `tolower` from `libc.so.6`, and expects `97`.
- `test/test_c_import.pas`: compiles a local C definition from
  `test/my_c_lib.c` and expects `42`, including a preceding prototype to
  ensure a local body wins over external resolution.

## Compiler Tracing

Use `--debug` before the source path to enable compiler tracing:

```sh
./compiler/pascal26 --debug test/hello.pas /tmp/hello
```

The trace reports lexer/parser diagnostics already present in the compiler.
It is intended for diagnosing compiler execution; ELF debug symbols for
stepping through generated executables are a separate future enhancement.
