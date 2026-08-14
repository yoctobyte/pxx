---
track: A
prio: 70
type: bug
summary: "`--threadsafe` segfaults on EVERY NilPy program, including a one-line `print(\"hi\")`. Pre-existing — the pinned stable does it too. Invisible because the Makefile has ZERO --threadsafe .npy jobs, so no tier covers the combination. It is also the blocker behind the single finding of the --strict-uses corpus sweep, whose diagnostic tells you to rebuild with the flag that crashes."
---

# `--threadsafe` segfaults on every NilPy program

- **Type:** bug (silent, total) — **Track A** (the thread PAL / runtime is A's;
  route to N if it turns out to be pyeval/pylib init).
  Found by Track T on 2026-08-14 while running
  [[task-t-strict-uses-corpus-sweep]]. **T owns the tool, never the bug.**

## Reproduce — one line is enough

```
$ printf 'print("hi")\n' > /tmp/simple.npy
$ ./compiler/pascal26 --threadsafe /tmp/simple.npy /tmp/x
ok: /tmp/x  [code=... procs=...]
$ /tmp/x
Segmentation fault (core dumped)      # rc=139
```

It **compiles clean** and dies at run time. Faults at `0x4009f3` with a
corrupted stack (gdb shows garbage frames — `0x20`, `0x300000002`), so it is
early and it is not a null deref in ordinary code.

## The boundary is exactly the frontend

| source | flag | result |
|---|---|---|
| `.pas` (`WriteLn(42)`) | `--threadsafe` | **works** — prints 42 |
| `.npy` (`print("hi")`) | *none* | **works** — prints hi |
| `.npy` (`print("hi")`) | `--threadsafe` | **SIGSEGV** |

So neither the flag nor the frontend is broken alone; it is the combination.

**Pre-existing, not a fresh regression.** `stable_linux_amd64/default/pinned`
segfaults identically, so this has been shipping in the pin.

## Why nobody noticed

```
$ grep -n 'threadsafe' Makefile | grep -c 'npy'
0
```

**Zero** `--threadsafe` `.npy` jobs anywhere. Every tier that runs `--threadsafe`
runs it on Pascal, and every tier that runs NilPy runs it without the flag. The
combination has never been executed by any gate, on any box, ever — which is why
a total failure of a shipped flag went unnoticed rather than being caught the
day it broke.

## It is also blocking the `uses` campaign

The `--strict-uses` corpus sweep produced exactly **one** finding in 1660
sources: `test/test_nilpy_dotted_package_import.npy` errors with
`__pxx_pipe2 needs the thread-safe runtime: rebuild with --threadsafe`. Under
strict there is then **no working configuration** for that file:

| flags | result |
|---|---|
| (baseline) | compiles, runs, correct |
| `--strict-uses` | compile error telling you to add `--threadsafe` |
| `--strict-uses --threadsafe` | compiles, then `undefined symbol: __pxx_malloc` |
| `--threadsafe` | compiles, then SIGSEGV |

The diagnostic's advice is unusable because the flag it names is broken. So
[[bug-pascal-uses-is-transitive]] — the p80 reopened root-cause ticket — is
one file away from clear, and this is that file.

Note the two failure modes differ (`__pxx_malloc` undefined vs SIGSEGV), which
suggests the strict path and the plain path break at different points. Worth not
assuming one fix covers both.

## Coverage, once it is fixed

Track T should enrol a `--threadsafe` `.npy` job so this cannot recur silently.
**Deliberately not enrolled now** — a job that fails on the day it lands makes
the tier red for a known cause, which is the failure mode
[[bug-t-three-network-tests-flake-and-cost-real-debugging-time]] was closed to
remove. Filed as a follow-up on this ticket instead.

## Gate

`printf 'print("hi")\n' | --threadsafe` runs and prints `hi`; the same for
`test/test_nilpy_dotted_package_import.npy`; and `--strict-uses --threadsafe` on
that file both compiles and runs. Then Track T enrols the combination.
