---
track: C
prio: 40
type: feature
summary: "The C entry stub is `call main; exit_group(retval)`, so a plain `return` from main skips __pxx_run_finalizers entirely — which is why crtl cannot implement atexit without looking implemented and silently skipping handlers on the commonest exit path"
status: done
owner: claude-ACPN
---

# The C entry stub must run the finalizers, or `atexit` cannot exist

- **Type:** feature — Track C (the C entry stub / `cparser.inc`), with a Track A
  half if the shell itself moves
- **Opened:** 2026-08-09
- **Filed by:** Track B, closing out
  [[feature-b-crtl-last-seven-unimplemented-declarations]]. `atexit` is the last
  declared-but-unimplemented crtl function, and it is the one that cannot be
  finished inside crtl. The ticket says to split it out; this is that split.

## Why crtl cannot do this alone

crtl owns `exit()`, so registering handlers and running them there is easy. It
does **not** own the other exit path: the C entry stub is `call main;
exit_group(retval)`, emitted by the compiler, and a plain `return` from `main`
bypasses crtl entirely.

So a crtl-only `atexit` would run handlers for `exit()` and **silently skip them
for `return`** — for the commonest exit path in C. That is strictly worse than
not having it, because a body-less declaration at least fails loudly at link
(`undefined symbol: atexit`), whereas a half-wired one looks implemented and
produces a plausible wrong result. Which is this project's worst failure class,
so it was deliberately not done.

## The mechanism already exists

`__pxx_run_finalizers` / `EmitFinalizerRunnerBody` (`symtab.inc:5616`,
`cparser.inc:8453`) is the shell every Pascal exit path calls. The C entry stub
does not call it. Wiring it in — so both `return` from `main` and `exit()` run
registered handlers, in LIFO order — is the whole change.

## Then, and only then

Track B adds the handler table in crtl against it, and
`tools/crtl_decl_probe.sh` reaches 0 unimplemented (it is at 1 as of 2026-08-09,
`poll` having landed).

## Gate

`atexit` handlers run in LIFO order for BOTH exit paths — a `return` from `main`
and an explicit `exit()` — matching gcc in `tools/gcc_diff_probe.sh`, plus the
existing C suites staying green (the stub is on every C program's path, so this
is not a narrow change).

## 2026-08-09: this unblocks `environ` too, not just `atexit`

Found bringing up tcc ([[feature-crtl-implement-libc-assumptions]]). `tcc.c`
builds and runs now, but warns:

```
warning: undeclared identifier 'environ' used as value (treated as 0)
```

so `char **envp = environ;` silently becomes NULL.

crtl already HAS the environment — `stdlib.c` loads `/proc/self/environ` into
`pxx_env_buf` for `getenv()`. The blocker is the same shape as this ticket's:
`environ` is a VARIABLE read directly, with no call to trigger the lazy load, so
it must be populated **before `main`** — and the C entry stub has no init phase,
just as it has no fini phase.

So the change this ticket describes is worth more than it says: **one entry-stub
change unblocks both** the last declared-but-unimplemented crtl function
(`atexit`) and a silent-wrong-value `environ`. Consider raising its priority
accordingly — the `environ` half is the silent-wrong-answer class, which this
project ranks worst.

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.

## Resolution (2026-08-10) — the fini half, on all five targets

The C entry stub now calls `__pxx_run_finalizers` between `call main` and
`exit_group`, so a plain `return` from `main` is no longer a silent skip.

**`EmitCallProc` did the work.** It is target-independent and resolves the
runner as a forward (`EmitFinalizerRunnerBody` emits the body later) — the same
call NilPy's program epilogue makes. So the per-target part was only **saving
`main`'s return value across the call**, two instructions each, with stack
alignment preserved:

| target | save / restore |
| --- | --- |
| x86-64 | `push rax` ×2 / `pop rax` ×2 (keeps rsp 16-aligned) |
| i386 | `push eax` / `pop eax` |
| arm32 | `str r0, [sp, #-8]!` / `ldr r0, [sp], #8` |
| aarch64 | `str x0, [sp, #-16]!` / `ldr x0, [sp], #16` |
| riscv32 | `sw a0` in a 16-byte frame / `lw a0` |

### Proved end to end, not just emitted

The byte pattern is present and the call target resolved (non-zero rel32). But
emission is not execution, so it was proved by **temporarily** giving
`lib/rtl/pxxcio.pas` a `finalization` section and running a C program that only
`return 3`s:

```
main-returns
FINALIZER-RAN
exit=3
```

Finalizer runs AFTER main returns, and the exit code survives the call. The
`pxxcio` edit was reverted immediately and is not in this change.

### It is a no-op today — deliberately, and worth knowing

**No currently auto-pulled unit has a `finalization` section** (checked
`pxxcio`, `builtinheap`), so nothing observable changes yet: the runner walks an
empty list. Confirmed by differential — **all 385 `test/*.c` run under the new
binary and under `pinned` with zero differing output or exit codes**. That is
the intended shape: a live but inert hook that Track B can now build the
`atexit` handler table against.

**Verification split:** x86-64 and i386 run natively (exit code preserved,
checked at 7 and 42); arm32 / aarch64 / riscv32 are compile-checked here and
their runtime is Track T's matrix — the standard "confirm native, offload the
matrix" split.

**Regression test:** `test/cfinalizers_on_main_return_b379.c`, wired into the
Makefile. It pins the compiler's half — main's return value surviving the
finalizer call — because the handlers-actually-ran half needs crtl's table and
cannot be asserted from here yet.

### What this unblocks, and what it does NOT

- **Unblocks** [[feature-b-crtl-last-seven-unimplemented-declarations]]: Track B
  can add the `atexit` handler table and reach 0 unimplemented. `atexit` today
  is still a body-less declaration — `undefined symbol: atexit` at run time,
  verified — which is the loud failure the ticket wanted preserved until the
  table exists.
- **Does NOT fix `environ`.** The 2026-08-09 note is right that one entry-stub
  change covers both, but they are different halves: `environ` needs an **init**
  phase (populated *before* `main`), and this added only the **fini** phase.
  `char **envp = environ;` still silently becomes NULL. Filed as
  [[feature-c-entry-stub-must-run-initializers-for-environ]] rather than left
  implied by this ticket's title.

**Gate:** `tools/gate.sh quick` GREEN (self-host fixedpoint + testmgr quick +
FPC seed canary), all 385 C tests differentially identical to `pinned`, five
targets compile, `make test-nilpy` green.
