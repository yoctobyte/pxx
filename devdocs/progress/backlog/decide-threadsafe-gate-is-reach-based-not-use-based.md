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
`__pxxclone` is PARSED, not when a thread is created.** It is an `Error()` in
`compiler/parser.inc:11792`, raised the moment the parser walks over the
`__pxxclone` identifier inside `PalThreadCreate`'s body. Minimal demonstration —
this fails, and it never spawns anything:

```pascal
program g1;
uses palthread;
begin writeln('never spawns a thread'); end.
```

```
error: __pxxclone (thread creation) requires --threadsafe or {$threadsafe on}
```

## Corroboration found the same day, independently

`tools/crtl_decl_probe.sh` reports **20 build-failures, all of them `pthread.h`**
— `pthread_mutex_init`, `_lock`, `_unlock`, `pthread_once`, `pthread_self`, the
whole family:

```
error: __pxx_pmutex_init needs the thread-safe runtime: rebuild with --threadsafe
```

`pthread_mutex_lock` does not create a thread either. That is a second,
independent instance of the same shape, with 20 declared C symbols behind it,
reached from a completely different direction (a C-side probe rather than a
Pascal uses clause). Three instances now: syncobjs (fixed by splitting
`palfutex`), `Classes`, and crtl's pthread surface.

## Options

1. **Leave it.** `TThread` stays in `palthreadobj`; portable threaded sources
   keep their `{$IFDEF FPC}` uses-clause split forever. Cheapest, and it leaves
   the mission line ("compile real-world code as-is") failing on every threaded
   Pascal program in existence — which is how this ticket got filed.
2. **Make the gate use-based (Track A).** Error when a thread is actually
   created, not when the unit is parsed. Then `classes` can re-export `TThread`
   for +10.6 KB, portable sources compile unedited, and the gate still catches
   every program that really spawns.

   **This is more work than it first looks, and an earlier draft of this ticket
   understated it.** Moving the check from parse to codegen is NOT enough by
   itself, because pxx emits every unit procedure whether or not anything calls
   it — measured: adding one never-called procedure to a used unit grows the
   binary by +1 proc and +235 bytes.

   ```
   without the uncalled proc:  code=84115B  procs=188
   with it:                    code=84350B  procs=189
   ```

   So `PalThreadCreate`'s body is codegen'd for anyone who touches the unit,
   `IR_CLONE` is emitted, and a codegen-time gate fires exactly as often as the
   parse-time one. A genuine use-based gate needs **reachability from the
   program entry** — a call graph the compiler does not currently build.

   Worth noting the same analysis buys procedure-level dead-code elimination,
   which is valuable on its own (every `uses classes` program today carries
   every `classes` procedure). That may make this one job rather than two.
3. **`--threadsafe` becomes the default** and the flag turns it off. Removes the
   gate entirely at the cost of the thread-safe heap/ARC/console path in every
   program.

   **Now measured** (this was the "number nobody has measured yet"). The flag
   turns ARC refcount inc/dec into `lock`-prefixed ops (`ir_codegen.inc`), locks
   the heap allocator (`ir.inc`), and wraps console I/O statements in a
   reentrant spinlock (`IR_IO_LOCK`). On a string/heap-heavy loop —
   800 000 `IntToStr` + concatenations, so ARC and allocator traffic throughout —
   best-of-9 user CPU on an otherwise busy box:

   | build | user CPU | code |
   | --- | --- | --- |
   | default | **0.76 s** | 212 329 B |
   | `--threadsafe` | **0.87 s** | 214 229 B |

   **~14% on allocation-heavy single-threaded code**, +1.9 KB. That is a real
   tax to put on every program that never starts a thread, and it argues for
   keeping the flag and fixing the gate rather than removing the flag.
4. **Re-export `TThread` from `classes` and require `--threadsafe`** for all
   Classes users. Rejected here on the measurement above, recorded so the option
   is visibly considered rather than missed.

## Recommendation

**Option 2**, with eyes open about the cost. It is the same correction the
palfutex split made — stop charging code for what it *sits next to* rather than
what it *does* — and it is the one that makes item 1 of the compat ticket a
five-line change afterwards. But it needs a reachability pass the compiler does
not have, so it is a real piece of Track A work, not a diagnostic tweak.

The measured 14% tax rules option 3 out as a silent default, and the
compile-break rules option 4 out. That leaves 1 (do nothing, portable threaded
sources keep their ifdefs forever) against 2 (build the reachability pass and
get procedure-level DCE with it). That is the actual choice.

## What shipped anyway

Items 2, 3 and 4 of the compat ticket needed no decision and are done: an empty
`cthreads` shim, `TThread.WaitFor` as a `function: LongWord` returning
`ReturnValue`, and `BeginThread`/`EndThread`/`TThreadID`/
`WaitForThreadTerminate`/`CloseThread`. Only item 1 waits on this.
