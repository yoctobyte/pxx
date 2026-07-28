---
track: B
prio: 45
type: feature
---

# No access to environment variables anywhere in the RTL

`grep -rn "getenv\|environ" lib/rtl compiler/builtin` finds nothing: pxx programs
cannot read their environment. Neither Pascal (`GetEnvironmentVariable`) nor
NilPy (`os.environ`, `os.getenv`) has anything to bind to.

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

## Gate

`make test` + a test that reads a variable the harness sets, and a `.npy` doing
the same through `os.environ.get`, both diffed against CPython.
