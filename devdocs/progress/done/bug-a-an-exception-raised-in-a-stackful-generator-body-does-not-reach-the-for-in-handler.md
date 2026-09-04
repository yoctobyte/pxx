---
track: A
prio: 65
type: bug
blocked-by: []
summary: "FIXED: the stackful generator body prologue now links its exception chain to the resumer's, read from [[self + CO_OFF_CALLERCTX]] -- no new intrinsic needed, because CoSwitch pushes exc_top last before storing rsp. CoAlloc had seeded it with 0 (`fresh chain on this stack`) so a raise walked an EMPTY chain and killed the process. Five-row test: two controls that were green before, the guard, and two that say it did not swing too far. The once-at-entry link is safe because `yield` inside try/except is REJECTED by the compiler, so a generator handler is never live across a suspension."
status: done
owner: frankb-78
---

# An exception in a stackful generator body never reaches the for-in's handler

- **Track A.** Measured 2026-09-04 by frankb-78 while trying to measure
  `bug-a-a-generator-body-raising-past-a-managed-temp-is-not-covered-by-the-unwind-landing-pad`.
  It is why that ticket's measurement is stackless-only.

## The three-way control

Same `Once` in all three — `try ... except on E: Exception do Inc(caught) end`,
run 3 times, `gmsg` a global AnsiString:

| what raises | result |
| --- | --- |
| a plain `procedure Plain` called inside the try | `caught=3` |
| `function Gen(n): Integer; generator; stackless;` driven by `for x in Gen(1)` | `caught=3` |
| `function Gen(n): Integer; generator;` (stackful, coroutine) — same source otherwise | **`Unhandled exception: Exception: helloA`**, process dies on the first iteration |

The try is the same try, the raise is the same raise, and only the generator
form changes. This is not the handler failing to match.

## Why it is plausible on this path and not the other

A stackful generator body runs on its OWN coroutine stack and is entered by
`CoSwitch` `ret`ing into it rather than by a call. The exception chain head is
per-thread (`EXC_TOP`), so a raise on the coroutine stack walks a chain whose
frames belong to the consumer's stack — there is no handler on the generator's
own stack, and whatever it finds is not reachable by the unwind it then
performs. A stackless step function is an ordinary call on the ordinary stack
and has none of this.

## What this blocks

- The unwind-landing-pad ticket above could only be measured for the stackless
  form; the stackful frame's behaviour is **UNCHECKED**, not fine.
- `bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in`
  likewise.

## The guard this needs

The three-way control above, as a test, once it is fixed — the stackful row is
the guard and the other two are the controls that say the harness works. Note
that the failure is a process death, so a value assertion catches it without
any census.

## Resolved — link the chain to the resumer's at body entry

`CoAlloc` seeds the coroutine context's saved `exc_top` with 0 — its own comment
says so, *"fresh chain on this stack"* — and `CoSwitch` restores it on the way
in, so a raise on the coroutine stack walked an empty chain, found no handler
and killed the process. **This was a design choice, not an oversight**, which is
why the fix had to say what the right semantics are rather than just patch.

**Not a Track U fork.** Two independent sources already answer it: pxx's own
STACKLESS generators propagate to the consumer (`caught=3` on the identical
source), and so does the language. What was open was the implementation, which
is mine to pick.

**The consumer's chain head needs no new intrinsic.** `CoNext` calls `CoSwitch`
with `pfrom = &callerctx`, and `CoSwitch` pushes `exc_top` LAST (lowest address)
before `mov [pfrom], rsp` — so `[[self + CO_OFF_CALLERCTX]]` is exactly the
chain the consumer was running with. Three instructions in the generator body
prologue, where the instance is already in `rbx`. No nil guard: `callerctx` is
written on the way in and cannot be 0 at body entry, and a guard would have to
branch over `EmitStatusSlotX64`, whose length is not fixed (the threadsafe build
takes a `gs:` prefix) — a hand-counted distance over a variable-length emitter
is a worse hazard than the one it guards.

## The five rows, and what each is for

| row | before | after |
| --- | --- | --- |
| a plain procedure raising inside the try | caught 5 | caught 5 — **control** |
| `generator; stackless;` raising | caught 5 | caught 5 — **control** |
| `generator;` (stackful) raising | **process dies, rc=217** | caught 5 — **guard** |
| a generator catching its OWN raise, then yielding again | ok | ok — did not swing too far |
| a raise past the generator's own non-matching handler | died | reaches the consumer |

Rows 1 and 2 were green before the fix. They are in the test because without
them a reader cannot tell "the guard fires" from "the harness is broken".

## The row that CANNOT be written, and why that is load-bearing

There is no row for *"the consumer raises while the generator is suspended
inside its own try"* — the case where an inherited chain would be stale in the
dangerous direction. **`yield` inside `try/except/finally` is rejected by the
compiler** (*"yield inside try/except/finally is not allowed (v1)"*), so a
generator's handler frame can never be live across a suspension. That refusal,
which exists for unrelated reasons, is what makes a once-at-entry link safe
rather than merely convenient.

## The assumption, written where it can be violated

The link is made ONCE, at first entry, so it holds only while the resumer's
frame outlives the coroutine. True today because `CoAlloc` and `CoNext` have
exactly one caller — the for-in desugar — which creates and resumes in the same
frame and resumes at the loop HEAD, outside any try the loop BODY pushes.
**Nothing enforces that uniqueness**, so the constraint is stated at both call
sites (`lib/rtl/coroutine.pas`'s `CoAlloc` and the desugar's `paCoAlloc` lookup),
not only at the prologue that depends on it — a second driver would have to
refresh the link per resume, and the failure mode if it does not is a longjmp
into a returned frame, which would not point back here.

## What this fix COSTS, measured

It turns a process death into a working program that leaks. An exception
escaping the loop skips the teardown that calls `CoFree`, so each escaping raise
loses the coroutine's 64 KB stack plus the instance — RSS 9324 kB at N=2000 and
36844 kB at N=8000, a 4.59 kB/raise slope of touched pages against a 64 KB
reservation. Recorded on
`bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in`,
which this measurement moved from UNCHECKED-for-stackful to its largest case,
and it is why the new test runs N=5.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit a090fa76d.
