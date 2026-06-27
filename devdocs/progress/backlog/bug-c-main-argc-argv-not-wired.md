# C `main(argc, argv)` gets argc 0

- **Type:** bug (Track C / C program entry ABI)
- **Status:** backlog
- **Owner:** —
- **Found / Opened:** 2026-06-27, while switching `make test-lua` to load
  scripts from files after crtl `fopen` landed.

## Symptom

C programs can declare `int main(int argc, char **argv)`, but the generated entry
path does not pass the process argc/argv values into that C function. A simple
probe exits as if `argc < 2` even when invoked with an argument:

```c
#include "stdio.c"

int main(int argc, char **argv) {
  if (argc < 2) return 1;
  printf("%s\n", argv[1]);
  return 42;
}
```

Observed:

```text
$ /tmp/cargv_probe xyz
exit=1
```

## Impact

Real C programs cannot naturally consume command-line arguments. The Lua test
runner currently works around this by copying each script to a fixed
`/tmp/pxx_lua_input.lua` path and using `luaL_loadfile`, instead of passing the
script path as `argv[1]`.

## Acceptance

- A C `main(int argc, char **argv)` receives real argc/argv on x86-64.
- Add a C regression that invokes the compiled binary with an argument and
  verifies `argc >= 2` and `argv[1]`.
- If practical, keep the no-argv `int main(void)` path unchanged and avoid
  forcing argv setup into binaries that cannot observe it.

## Log

- 2026-06-27 — Filed from the Lua file-backed runner work. Existing Pascal
  `ParamCount` / `ParamStr` argv support is separate; this is the C frontend's
  `main` call/entry ABI.
