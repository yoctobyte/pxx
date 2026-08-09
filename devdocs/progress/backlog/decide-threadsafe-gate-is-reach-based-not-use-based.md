---
track: U
prio: 45
type: decide
summary: "Putting TThread in Classes where FPC code looks for it is not a size trade-off — MEASURED, it makes every `uses classes` program require --threadsafe, because the gate fires on REACHING __pxxclone's unit rather than on calling it. Same wall the palfutex split just removed one level down, but splitting cannot fix this one"
---

# Should the `--threadsafe` gate be use-based rather than reach-based?

- **Type:** decide — Track U
- **Opened:** 2026-08-09
- **Filed by:** Track B, doing
  [[compat-pascal-thread-api-surface-differs-from-fpc]]. That ticket says of its
  first item — put `TThread` in `Classes` — *"Worth a Track U call if the
  size/dependency trade-off is not obvious — do not just do it."* Measured
  first; the trade-off turns out not to be about size at all.

## What was measured (pinned, 2026-08-09)

`lib/rtl/classes.pas` with `palthreadobj` added to its uses clause, compiling a
program that only builds a `TStringList`:

```
uses sysutils, platform, palthreadobj;
->  pascal26:172: error: __pxxclone (thread creation) requires --threadsafe or
    {$threadsafe on}: the default heap/ARC/console-I/O runtime is not thread-safe
```

**Every `uses classes` program stops compiling** unless it passes
`--threadsafe`, whether or not it has ever heard of a thread. That is not a
trade-off to weigh, it is a break, so item 1 of the compat ticket cannot be done
as written.

With `--threadsafe` supplied, the size cost is real but unremarkable — for
reference, not as the deciding number:

| build | code | data | procs |
| --- | --- | --- | --- |
| classes today, `--threadsafe` | 244 899 | 20 700 | 632 |
| classes + palthreadobj, `--threadsafe` | 255 519 | 22 380 | 689 |

+10.6 KB of code and 57 procedures. Affordable. The compile break is the blocker.

## The shape — the same wall, one level up

This is exactly [[bug-b-futex-helpers-are-trapped-behind-pxxclone]], which was
fixed the same day: `PalFutexWait` was gated because it *shared a unit* with
`__pxxclone`, and splitting `palfutex` out removed the gate without weakening
anything, because waiting on a word genuinely does not create a thread.

That escape does not exist here. `TThread.Start` genuinely calls `__pxxclone`.
Splitting cannot separate them, because they are the same feature.

So the real question is one level down: **the gate fires when a unit containing
`__pxxclone` is REACHED, not when `__pxxclone` is CALLED.** A program that
declares a `TStringList` and never spawns anything is refused for code it does
not execute and, after dead-code elimination, may not even contain.

## Options

1. **Leave it.** `TThread` stays in `palthreadobj`; portable threaded sources
   keep their `{$IFDEF FPC}` uses-clause split forever. Cheapest, and it leaves
   the mission line ("compile real-world code as-is") failing on every threaded
   Pascal program in existence — which is how this ticket got filed.
2. **Make the gate use-based (Track A).** Error at the `__pxxclone` CALL SITE
   reachable from the program, not at unit reach. Then `classes` can re-export
   `TThread` for +10.6 KB, portable sources compile unedited, and the gate still
   catches every program that actually spawns. Cost: the compiler must decide
   "is this call reachable", which is a real analysis rather than a flag check —
   though the conservative version ("did anything in the program reference a
   symbol whose body calls `__pxxclone`") is close to what is already tracked
   for lazy stub emission (`EnsureCloneStub` emits on first `IR_CLONE` codegen,
   which is already use-based — the *diagnostic* is the part that is not).
3. **`--threadsafe` becomes the default** and the flag turns it off. Removes the
   gate entirely at the cost of the thread-safe heap/ARC/console path in every
   program. Needs the performance number nobody has measured yet.
4. **Re-export `TThread` from `classes` and require `--threadsafe`** for all
   Classes users. Rejected here on the measurement above, recorded so the option
   is visibly considered rather than missed.

## Recommendation

**Option 2.** It is the same correction the palfutex split made — stop charging
code for what it *sits next to* rather than what it *does* — and it is the one
that makes item 1 of the compat ticket a five-line change afterwards. Worth
noting that the stub EMISSION is already use-based, so the diagnostic is the
part that is out of step with the rest of the machinery, which is usually a sign
the diagnostic is the bug.

Option 3 is worth a number even if it is not chosen, because "how much does the
thread-safe runtime actually cost" is unmeasured and keeps being assumed.

## What shipped anyway

Items 2, 3 and 4 of the compat ticket needed no decision and are done: an empty
`cthreads` shim, `TThread.WaitFor` as a `function: LongWord` returning
`ReturnValue`, and `BeginThread`/`EndThread`/`TThreadID`/
`WaitForThreadTerminate`/`CloseThread`. Only item 1 waits on this.
