---
track: A
prio: 70
type: bug
summary: "`--threadsafe` segfaults on EVERY NilPy program, including a one-line `print(\"hi\")`. Pre-existing — the pinned stable does it too. Invisible because the Makefile has ZERO --threadsafe .npy jobs, so no tier covers the combination. It is also the blocker behind the single finding of the --strict-uses corpus sweep, whose diagnostic tells you to rebuild with the flag that crashes."
status: done
owner: agent-an
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

---

## Root cause — TWO defects, same shape, and the first fix exposed the second

Both are *state that only the Pascal driver set up, consumed by code that every
frontend reaches*. Neither is in the threading runtime; the ticket's guess that
it might be "pyeval/pylib init" was wrong in a useful way — it is neither the
frontend nor the flag, it is the **driver**.

### 1. `IOLockAddr` stayed 0 → a call to the ELF entry point

`EmitIoLockStubs` was invoked from `ParseProgram` — the *Pascal* driver — and
nowhere else. The other **eight** drivers (NilPy, C, Rust, Zig, Basic, Elisp,
Whitespace, Ada) never emitted the stubs, so `IOLockAddr` kept its initial 0 and
`IR_IO_LOCK` lowered to `call <code offset 0>`.

Code offset 0 is **the ELF entry point** — the header occupies the bytes before
it, so offset 0 is `0x4000b0`. And the entry stub ends by *jumping* to main
rather than returning. So `call 0` builds a perfect infinite loop:

```
main → entry(0x4000b0) → mmap a fresh 256 MB arena → jmp main → …
```

Each lap pushes 8 bytes of return address and never pops. After ~1M laps the
8 MB stack is gone and the fault lands on whatever ordinary instruction touched
the stack next — which is exactly why the reported backtrace was garbage
(`0x20`, `0x300000002`) and pointed nowhere near the cause.

The measurement that cracked it: **the frame-pointer chain was only two frames
deep**, terminating in a nil saved `rbp`. That rules out deep recursion and says
the stack was consumed *without* frames — which only a `call` that never returns
can do. `rsp` sat exactly on the low page of `[stack]`.

### 2. `BSS_IO_OWNER` and `BSS_IO_DEPTH` aliased onto the same eight bytes

With the stubs emitted, it **still hung** — now spinning in the acquire loop
instead of faulting. Same disease, second organ: the two BSS slots were also
allocated only by `ParseProgram`, so for every other driver both stayed 0 and
the owner tid and the reentrancy depth were *the same qword*. The disassembly is
unambiguous — `lock cmpxchg …,0x5fc500` and `incq 0x5fc500`, one address:

```
0x400166:  lock cmpxchg %rcx,0x5fc500     ← owner
0x400174:  incq   0x5fc500                ← "depth"
```

`inc [depth]` scribbled on the owner tid, so nothing could ever win the
cmpxchg, and the stub spun forever. **A lock whose two fields alias is not a
lock.**

## The fix — one place, plus a guard for the class

`EmitIoLockStubsForTarget` (in `ir_codegen.inc`) is now the single thing that
decides what a `--threadsafe` build needs: the per-arch stub choice **and** the
two BSS slots, allocated together. Splitting those two is literally what turned
the first fix into the second bug, so they are now impossible to allocate apart.
All nine drivers call it; none spells out the choice itself. riscv32/xtensa are
deliberately excluded (no threadsafe atomics there, and `AN_WRITE` does not emit
`IR_IO_LOCK` for them, so a stub would be dead bytes).

`IREmitCodeCall` now **errors on address 0**. Every one of its ~50 callers
passes a `*Addr` stub variable and none legitimately passes 0, so one check at
the choke point converts this entire failure class — *silent runtime hang, far
from the cause* — into a compiler error that names it.

That guard is the real deliverable, because **this shape had already bitten
once**: the identical "driver forgot a stub, address stayed 0" hole was fixed
for `Div0StubAddr`, by **copying the line into each driver**. Nine copies is
what let it drift again here. `pyparser.inc` even carries the comment "same
latent hole as the C driver" — the pattern was *documented* and still recurred,
which is the argument for a choke-point check over a ninth copy.

## Where the ticket's guesses landed

- "route to N if it turns out to be pyeval/pylib init" — **no**, nothing to do
  with NilPy internals; the same bug hit seven other frontends.
- "the boundary is exactly the frontend" — **right, but for the driver, not the
  language**. C looked healthy only because `printf` is a crtl call that never
  emits `IR_IO_LOCK`; the C driver had the identical hole, latent.
- SIGSEGV vs hang: both, depending on where the runaway stack lands. Under gdb
  it faulted at `0x4009f3` as reported; bare it hung, because the fault handler
  spun. Same bug.

## Coverage

`test/test_threadsafe_nilpy_io.npy`, in the `threads` target, as a
**differential** against the same source built without the flag (plus a literal,
since the two could in principle be wrong together). Pinning only a literal
would rot; pinning only the differential would miss both arms breaking alike.

Its nested write — a `print` whose *argument* prints — is not decoration: it is
the only thing that exercises the reentrancy depth counter, and **a flat
`print` passes with the fields still aliased**. Cause 2 is invisible without it.
Output also matches the CPython oracle.

This closes the coverage hole the ticket identified: every `--threadsafe` job
was Pascal, every NilPy job ran without the flag, so the combination had never
been executed by any gate on any box.

## Verified

| case | result |
|---|---|
| NilPy `print("hi")` `--threadsafe` | **fixed** (was hang/SIGSEGV) |
| NilPy / Pascal / C, with and without the flag | all correct |
| `test_nilpy_dotted_package_import.npy --threadsafe` | **runs** |
| i386 / aarch64 / arm32 Pascal `--threadsafe` | build; i386 runs |
| NilPy cross-compile | fails **identically without** the flag — pre-existing, unrelated |

Gate: `make compiler/pascal26` (fixedpoint) + `gate.sh quick` GREEN.

## Carved out, deliberately

`--strict-uses --threadsafe` on that file still dies with `undefined symbol:
__pxx_malloc` — a **different mechanism**: under strict, the pxxcio bridge
functions become undefined *dynamic imports* instead of resolving to their
Pascal bodies (`objdump -T` shows five `__pxx_*` as `DF *UND*`; the plain
`--threadsafe` build has none). Not a missing `uses` — both `.c`-pulling `lib/pcl`
units already carry `uses pxxcio` explicitly.

Filed as
[[bug-c-strict-uses-turns-pxxcio-bridge-into-undefined-dynamic-imports]].
The ticket's own warning — "the two failure modes differ… worth not assuming one
fix covers both" — was correct.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
