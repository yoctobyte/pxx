# Implement C interop regression test for dynamic loading and runtime symbol invocation (`dlopen`/`dlsym`)

- **Type:** test
- **Status:** in-progress
- **Track:** C (C frontend interop testing)
- **Owner:** Antigravity
- **Opened:** 2026-06-28

## Motivation

To test dynamic loading of libraries "at will" at runtime and calling resolved functions through function pointers, we need a regression test for the POSIX dynamic linking loader interface (`dlfcn.h`).

This test will exercise:
1. Importing `<dlfcn.h>` and linking against `libdl.so.2` automatically.
2. Loading `libm.so.6`, `libz.so.1`, and `libcrypt.so.1` at runtime using `dlopen`.
3. Resolving symbol addresses (`cos`, `zlibVersion`, `crypt`) using `dlsym`.
4. Defining custom procedural types (e.g. `cdecl` function signatures) in Pascal.
5. Casting resolved symbol pointers (`Pointer`) to procedural types.
6. Invoking the runtime-resolved function pointers (passing floats and strings back and forth).
7. Releasing the library handles using `dlclose`.

## Scope

1. **Test implementation**:
   - Create `test/test_c_dlopen.pas`.
   - Verify dynamic invocation of `cos(0.0) = 1.0`.
   - Verify dynamic invocation of `zlibVersion()`.
   - Verify dynamic invocation of `crypt(...)`.
2. **Integration**:
   - Wire the test into the `test` target of the `Makefile`.

## Acceptance

- `test/test_c_dlopen.pas` compiles successfully.
- Executing the binary dynamically loads the target libraries, invokes the functions, asserts correct values, and exits with 0.

## Log
- 2026-06-28 — ticket opened and taken.
