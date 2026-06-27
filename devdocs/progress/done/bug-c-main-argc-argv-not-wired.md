# C `main(argc, argv)` gets real argc/argv

- **Type:** bug (Track C / C program entry ABI)
- **Status:** done
- **Owner:** —
- **Found / Opened:** 2026-06-27, while switching `make test-lua` to load
  scripts from files after crtl `fopen` landed.
- **Closed:** 2026-06-27

## Symptom

C programs can declare `int main(int argc, char **argv)`, but the generated entry
path did not pass the process argc/argv values into that C function. A simple
probe exited as if `argc < 2` even when invoked with an argument:

```c
#include "stdio.c"

int main(int argc, char **argv) {
  if (argc < 2) return 1;
  printf("%s\n", argv[1]);
  return 42;
}
```

Observed before the fix:

```text
$ /tmp/cargv_probe xyz
exit=1
```

## Impact

Real C programs could not naturally consume command-line arguments. The Lua test
runner worked around this by copying each script to a fixed
`/tmp/pxx_lua_input.lua` path and using `luaL_loadfile`, instead of passing the
script path as `argv[1]`.

## Fix

The C program entry stub now saves the initial process stack pointer and seeds
the SysV C argument registers before calling `main`:

- `edi = argc` from `[initial_rsp]`
- `rsi = argv` from `initial_rsp + 8`

This makes `int main(int argc, char **argv)` observe the real command line.
Extra register arguments remain harmless for `int main(void)`.

## Regression

Added `test/cmain_argv_b90.c`, wired into `make test-core`. It compiles a C
program and runs it as:

```text
/tmp/cmain_argv_b9026 ab xyz
```

The program verifies `argc >= 3`, loads `argv[1]` and `argv[2]` into `char *`
locals, checks both strings byte-by-byte, and returns `42` only on success.

Note: direct chained spelling such as `argv[1][0]` exposed a separate C
pointer-depth metadata bug and is tracked in
`bug-c-chained-pointer-index-loses-base-type`.

## Log

- 2026-06-27 — Filed from the Lua file-backed runner work. Existing Pascal
  `ParamCount` / `ParamStr` argv support is separate; this is the C frontend's
  `main` call/entry ABI.
- 2026-06-27 — Fixed by seeding `edi`/`rsi` from the saved initial stack before
  the C frontend's entry-stub `call main`; added `test/cmain_argv_b90.c`.
