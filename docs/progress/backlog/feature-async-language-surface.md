# Async language surface + stackless coroutine backend

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-cross-target-feature-parity
- **Opened:** 2026-06-16 (design discussion — async ergonomics, ESP, Nil Python)

## Motivation

The concurrency engine is shipped (coroutine scheduler + epoll reactor + channels
+ the `CoSwitch` primitive on all 4 Linux targets — see
feature-async-coroutines). Today you *use* it with bare calls: `Spawn(@Body, x)`,
`CoYield`, `WaitReadable(fd)`, `CoSleep(ms)`. No `async`/`await`. For **stackful**
coroutines that is correct and a feature — suspension is transparent (a stack
switch), so no coloring keywords are needed (Go/Lua/Erlang model).

But two forces want a real surface:

1. **A stackless coroutine backend** (state machine, no per-coroutine stack) is
   the RAM-cheap path for constrained devices. A stackless lowering *requires*
   suspension markers — the compiler must know where to split the state machine,
   and suspension is **transitive** (a coroutine calls `Foo` calls `Bar` which
   suspends → `Foo`/`Bar` must be transformed too). A per-call `await` marker is
   exactly what makes that transform **local** (no whole-program analysis, works
   with separate compilation / indirect calls). This is why Python *must* have
   `async`/`await`: its coroutines are stackless.
2. **Nil Python** (`.npy`) has `async def` / `await` as native, expected
   keywords. A Python programmer writes them. So the surface isn't optional
   there — it's the frontend's natural shape. (Pascal frontend: keyword-optional;
   Nil Python: native.)

Design principle: this **mirrors the generator surface we already shipped**
(`; generator;` + `yield` + `; stackful;` / `; stackless;`). Same two-backend
structure, same forcing directives, same auto-selection question.

## Surface (proposed)

| Generators (done) | Coroutines/async (this ticket) |
| --- | --- |
| `; generator;` routine directive | `; async;` routine directive |
| `yield` (suspension marker) | `await` (suspension marker) |
| `; stackful;` / `; stackless;` / auto | same |
| stackless = state-machine transform | stackless = state-machine transform |

- **`async` is non-viral** (deliberate divergence from Python): the directive is
  a hint, not hard coloring. Any function can still suspend on stackful. On a
  routine marked `; async;` the compiler MAY warn if a raw blocking syscall is
  used instead of the reactor. It is also what opts a routine into the stackless
  transform.
- **`await` always pays:**
  - *stackful:* documentation — marks the interleaving points (where another
    coroutine can run, so shared state may change). Incomplete re: transitive
    suspension (a plain call can still suspend) — say so in the docs. Optional.
  - *stackless:* mechanical + **required** — the marker that bounds the
    transform locally.
- Calls without `await` still work on stackful (it's a default); the keywords
  unlock stackless and document intent.

## Stackful vs stackless on device (ESP32)

Both are viable on ESP — correcting an earlier note that said stackful is out:

- **Stackful + small stacks first.** A coroutine stack does not need the hosted
  64 KB default (`CO_STK`); 4–8 KB fits ~40–75 coroutines in ~300 KB. Reuses the
  shipped engine — just make the stack size configurable and add a guard canary
  (overflow is the failure mode). **Make `CO_STK` configurable**, e.g. a
  per-build directive `{$COSTACKSIZE 8192}` (or a `Spawn`-time size arg, or a
  `; bigstack;` routine hint for the few deep ones). This is the fast path to
  real ESP multitasking and should land before the transform.
- **Stackless when small stacks aren't enough** (can't bound depth, or even
  4 KB × N is too much) — the state-machine transform, behind `; async;
  stackless;`.

## Mixing

Stackful and stackless coroutines can share one scheduler: tag each coroutine
with its strategy and resume it the right way (stackful → `CoSwitch`; stackless →
re-enter the step fn). The generator `for-in` already branches on
`ProcIsStackless` — same mechanism. Coexistence is mechanical; the only hard part
is **auto-deciding** stackless eligibility for transitive suspension. Practical
rule: default stackful (always works); auto-stackless only for locally-eligible
bodies; `; stackless;` to force.

## Build order (Pascal-first, Nil-Python-reused)

The stackless **generator** proved the machinery is frontend-agnostic: built and
tested in Pascal (cross-bootstrap + QEMU oracles), the transform/engine are
shared AST/IR. So:

1. **ESP stackful small-stack:** configurable `CO_STK` + canary. (Cheap; may even
   land independently of the surface.)
2. **Async surface in Pascal:** `; async;` directive + `await` marker; backend
   selection directives; non-viral `async`; stackful `await` = documentation.
3. **Stackless coroutine backend:** the transform behind the directive (the hard
   part). Auto-select only for locally-eligible bodies.
4. **Nil Python:** `async def` / `await` + a small `asyncio` shim (`sleep`→
   `CoSleep`, `run`→`Spawn`+`RunUntilDone`, `gather`→spawn-N-await-all) mapping
   onto the same AST nodes — near-free after the Pascal work.
5. (Optional) a `Task`/`Future` type for "spawn work, await its result"
   (`t := Spawn(...)`, `v := AwaitResult(t)`) — the one thing bare `await` over
   stackful doesn't give; expose as a function, keyword optional.

## Acceptance

`; async;` + `await` parse and lower on the Pascal frontend; the stackless
coroutine backend runs a multi-coroutine test byte-identical across targets (as
the stackless generator does); a configurable small coroutine stack runs the
scheduler suite; Nil Python `async def`/`await` lowers to the same engine.
Bootstrap + cross-bootstrap stay byte-identical.

## Log
- 2026-06-16 — opened from the async-ergonomics design discussion. Key
  conclusions: stackful needs no keywords (a feature); `await` is required only
  for the stackless transform (bounds transitive suspension locally) but is
  useful as documentation on stackful; build in Pascal first, reuse in Nil
  Python; ESP can run stackful with small/configurable stacks, stackless is the
  RAM optimization. Sequenced after classes-on-cross
  (feature-cross-target-feature-parity) so ESP/embedded isn't fighting two new
  fronts at once.
