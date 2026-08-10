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

## Detect at LEX time, not at lowering — this is what makes it cheap

> "and if we can detect it at lexer time the cost is minimal" — user, 2026-08-10

Correct, and the hook exists. Units are not lexed into private buffers: each one
is appended into the SAME token array by `LexAppend` (lexer.inc:2331), with
`MainProgramTokCount` marking the main program's boundary. So a unit's tokens
are scannable the moment it is lexed — **before it is parsed, lowered or
emitted**.

So the detector becomes a linear scan of the newly-appended token range after
each `LexAppend` (and after `LexAll` for the main program), looking for the
threading signals: `TThread`, `BeginThread`, `parallel` (the `parallel for`
gate), `__pxxclone`. If one appears and `ThreadSafeMode` is off — restart.

This is mechanically the same shape as NilPy's existing whole-module token scans
(`PyDefUsedAsValue`, `PyMethodUsedAsValue`, `PyDynAttrEverAssigned`), so it is a
pattern the codebase already runs, not a new kind of pass. The C frontend has
the same structure (`clexer.inc` uses `MainProgramTokCount` identically), so the
hook is available there too.

**The cost changes character.** Detecting at `__pxxclone` lowering means the
wasted work is a nearly-complete compile. Detecting at lex time means the wasted
work is *the lexing done so far* — a small fraction of a compile, and the
restart happens before any IR or codegen exists.

Residual inefficiency, worth stating so nobody is surprised: units are
DISCOVERED lazily through `uses` during parsing, so a threading signal inside a
unit pulled in late is still found late — you may have parsed earlier units by
then. Cheaper than today's failure either way, and it does not affect
correctness, only how much of the first pass is discarded.

A token scan is also deliberately coarse: it will fire on the identifier
`TThread` appearing anywhere, including a comment-adjacent mention or a name
that merely contains it. That is the right trade — a false POSITIVE costs a
thread-safe build (correct, slightly slower), while a false NEGATIVE is an
unlocked heap under real concurrency. Bias the scan toward firing.

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
3. ~~Should it be opt-in (`--threadsafe=auto`) rather than default?~~
   **DECIDED, user 2026-08-10: AUTO IS THE DEFAULT MODE, and its default
   OUTCOME is OFF.**

   > "no, auto is the default. and the default choice is OFF. BUT if programmer
   > decides to force it to off, and tries to use TThread or pthread, we will
   > simply error with a corresponding error. so, in general, by being auto,
   > it'll just work and default to OFF if we didnt detect any threading usage."
   > — user

   | invocation | behaviour |
   | --- | --- |
   | *(nothing)* — **auto** | detect at lex time. Nothing found -> **OFF** (fast, small, today's default build). Threading found -> turn it ON and restart. |
   | `--threadsafe` / `=on` | forced ON, as today |
   | `--threadsafe=off` | forced OFF. Using `TThread` / `pthread` / `parallel for` is then a **compile error** naming the conflict — the current gate message, but now attributable to the user's own `=off`. |

   So no flag is needed in either common case: a single-threaded program
   silently stays on the small unlocked runtime, and a threaded one silently
   gets a correct build. `=off` becomes the way to say "I know, and I want the
   small runtime anyway" — and then the gate error is the right answer, because
   the user asked for the contradiction.

   The principle, stated by the user and worth keeping: **the default OUTCOME is
   never ON.** OFF is what you get unless threading is actually detected. Auto
   is not "on by default" — it is "decide by evidence, and the evidence has to
   be there."

   **Note this raises the stakes on the detector.** Under `=auto`-by-default a
   false NEGATIVE silently produces an unlocked heap in a threaded program,
   where today it produces a hard error. That is the argument for biasing the
   scan toward firing (above), and for keeping the `__pxxclone` lowering gate as
   a LAST-RESORT backstop: if lowering reaches thread creation and the mode
   somehow resolved OFF, that must still fail loudly rather than emit.

4. **Interaction with the MCU targets** — `--threadsafe` is x86-64/i386/
   aarch64/arm32 only (compiler.pas:718). On xtensa/riscv32 auto must resolve to
   OFF and keep erroring on threading use, never attempt a restart that cannot
   succeed.

   Worth noting the earlier size worry largely evaporates under this shape: an
   MCU program that does not use threads is not detected, so it resolves OFF and
   gains nothing. One that DOES use threads needs the locks anyway.

## Prior art to not re-litigate

`uses cthreads` was considered as a detection trigger and rejected: it is a
Unix-FPC hack that Delphi sources do not have, so it covers only part of the
corpus. Reaching `__pxxclone` is the language-neutral signal and is what the
existing gates already key on.
