---
track: B
prio: 45
type: feature
---

# No access to environment variables anywhere in the RTL

## STATUS 2026-07-29: two of the three surfaces were already DONE

The description below was stale. Measured, not assumed:

| surface | state |
| --- | --- |
| Pascal `GetEnvironmentVariable` / `Count` / `String(i)` | **works** — sysutils reads `/proc/self/environ` through the PAL |
| NilPy `os.environ.get` / `os.getenv` | **works**, matches CPython |
| C `getenv` | **was still `return 0`** — fixed here |

`lib/crtl/src/stdlib.c` had `char *getenv(const char *name) { return 0; }` with
the comment "no environment yet", so C code compiled by pxx silently saw an
EMPTY environment: configuration read through `getenv()` simply never took
effect, with no diagnostic. It now reads `/proc/self/environ` once through
`__pxx_open`/`__pxx_read`/`__pxx_close` — the same source and the same
empty-on-failure rule as sysutils' `EnvLoad`, so a program that cannot see its
environment behaves like one started without one.

Verified against a gcc-built oracle on set / unset / empty-value and on the
prefix collisions a naive matcher gets wrong (`FOO` vs `FOOBAR` vs `FO` vs `""`).

Still open (see below): the `putenv` / write side was never decided, and the
implementation route note about reading envp off the initial stack was NOT
taken — everything goes through `/proc/self/environ`, which needs no codegen
and no per-target entry-stub work. That is a better answer than the one
sketched here; the stack route is only worth revisiting if a target without
`/proc` needs it (ESP has neither).

Found on songformatter's `convertrawtext.py`, which gates its debug chatter on
`os.environ.get("SONGFORMATTER_DEBUG")` — the wall the module now stops at
([[feature-demo-songformatter-pxx-target]]).

## Shape

The process environment arrives on the initial stack right after argv (the same
place `sys.argv` is already read from — see pylib's `pysys_argv`), so the data is
reachable without a syscall; it is a PAL-level accessor plus two surfaces:

1. **Pascal:** `GetEnvironmentVariable(name)`, `GetEnvironmentVariableCount` /
   `GetEnvironmentString(i)` (FPC's spelling) in sysutils.
2. **NilPy:** `os.environ` as a dict-like with `.get(name, default)` and `[]`,
   plus `os.getenv(name, default)`. `os.` is consume-and-deferred today, so this
   also needs the dotted-call table entry.

Writing (`putenv`/`os.environ[k] = v`) is a separate question — decide whether to
support it at all rather than half-support it.

## Implementation route (located 2026-07-28)

The data is already reachable; nothing needs a syscall.

- The program entry stub saves the initial stack pointer into a BSS global,
  `BSS_INITIAL_RSP` (`compiler/parser.inc:26953` reserves it, `:27310` stores
  rsp). `[initial_rsp]` is argc and `initial_rsp+8` is argv — that is exactly how
  `ParamStr` reads its argument (`EmitArgvToStringManaged`,
  `compiler/ir_codegen.inc:825`).
- **envp starts one slot past argv's NULL terminator**: `initial_rsp + 8*(argc+2)`.
- So the primitive is a `Pointer`-valued intrinsic returning that address, and
  everything above it — walking `char**`, splitting on `=`, comparing names — can
  be written in ordinary Pascal in sysutils. Only the intrinsic needs codegen,
  and only per target that should support it (x86-64 first; the cross targets
  each have their own entry stub, see the TARGET_ cases around `parser.inc:27310`).
- `lib/crtl/src/stdlib.c:50` is `char *getenv(const char *name) { return 0; }`
  with the comment "no environment yet" — point it at the same primitive so C
  code compiled by pxx gets a real environment too.

## Gate

`make test` + a test that reads a variable the harness sets, and a `.npy` doing
the same through `os.environ.get`, both diffed against CPython.

## RESOLVED 2026-07-31 — read side verified on all three surfaces

Re-measured end to end with one variable set in the parent shell:

| surface | probe | result |
| --- | --- | --- |
| NilPy | `os.environ.get(...)` / `os.getenv(...)` | both return the value |
| Pascal | `sysutils.GetEnvironmentVariable` | returns the value |
| C | `getenv` via `lib/crtl` | returns the value |

The write side (`setenv`/`putenv`, `os.environ[k] = v`) is deliberately NOT part
of this ticket — the question of whether a write should be visible to a spawned
child is a policy call and is now filed as [[decide-env-write-side]] rather than
half-answered here.

## Log
- 2026-07-31 — resolved, commit 2c9dc2317.
