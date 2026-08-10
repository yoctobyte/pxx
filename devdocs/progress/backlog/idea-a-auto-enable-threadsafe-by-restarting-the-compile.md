---
track: A
prio: 15
type: idea
blocked-by: []
---

# Auto-enable `--threadsafe` by voiding the compile and restarting

**WAIVED by the user, 2026-08-10 — "worth a ticket but i waive it for another
day."** Filed so the idea is not lost. Do not pick this up as ranked work; the
current explicit-switch design is correct and shipping
([[decide-ismultithread-runtime-flag-vs-compile-time-mode]], rejected).

> "it could even be that we start compiling, suddenly discover that something in
> our linked libraries _does_ use threads. and in that case, void all, enable the
> flag and compile with threading on.. an odd hack but.." — user

## The idea is cheaper than it sounds: the detector already exists

Two gates already fire the moment a build reaches threading without the flag,
and both currently just refuse:

```
parser.inc:11845   __pxxclone (thread creation) requires --threadsafe or {$threadsafe on}
parser.inc:19476   parallel for requires --threadsafe or {$threadsafe on}
```

The proposal changes only what happens on firing: instead of `Error`, set
`ThreadSafeMode := True`, discard all state, and re-run the compile from
scratch.

**And the restart is not the hack — it is required.** The flag cannot be flipped
mid-compile: the softlock define is applied *before lexing*, which is exactly
why `{$threadsafe on}` is already refused on i386/aarch64/arm32 and must be the
CLI flag there (lexer.inc:1601). So "void all and restart" is the only correct
shape, not a shortcut.

## Cost falls entirely on the case that needs it

A single-threaded program never trips a gate and pays **nothing**. A threaded
program compiled without the flag pays one extra full compile — and today that
program does not compile at all, so the comparison is against a hard failure,
not against a fast build.

## What it would and would not catch

- **Would**: `__pxxclone` reached through any path — including a Pascal unit or
  C library the user did not know spawns threads, which is the case that
  motivated this.
- **Would not**: a thread started by a route that never lowers through
  `__pxxclone` — inline asm, or C code linking a real `pthread_create` from
  outside crtl. That residual is the one already accepted on the rejected
  ticket, and this idea does not change it.
- Note `TThread` is a non-issue: it is hidden behind `{$IFDEF PXX_THREADSAFE}`,
  so that route already fails loudly at compile time.

## Open questions if it is ever taken up

1. **Is the restart in-process or a re-exec?** In-process means every global the
   compiler carries must be provably reset — the symbol tables, the ArrType
   table, `PendingInit`, the interned string pool, `BSSSize`. That is a long
   list and getting it wrong yields a corrupt second pass rather than a clean
   one. A re-exec of the compiler with `--threadsafe` appended is uglier and
   obviously correct; prefer it unless measured to matter.
2. **Should it be silent, or announce itself?** Silently changing the runtime
   model of a build is the kind of thing that surprises someone at 2am. A
   warning line ("threading detected in <unit>, recompiling with --threadsafe")
   costs nothing and keeps the build honest.
3. **Should it be opt-in** (`--threadsafe=auto`) rather than default? That keeps
   MCU and size-critical builds from silently gaining lock paths, which is the
   whole reason the flag is opt-in. Probably yes.
4. **Interaction with the MCU targets** — `--threadsafe` is x86-64/i386/
   aarch64/arm32 only (compiler.pas:718). On xtensa/riscv32 the gate must keep
   erroring, not attempt a restart that cannot succeed.

## Prior art to not re-litigate

`uses cthreads` was considered as a detection trigger and rejected: it is a
Unix-FPC hack that Delphi sources do not have, so it covers only part of the
corpus. Reaching `__pxxclone` is the language-neutral signal and is what the
existing gates already key on.
