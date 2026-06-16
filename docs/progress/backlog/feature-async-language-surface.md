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

## Decided spelling (locked 2026-06-16)

- Directive: **`; async;`** (+ `; async; stackful;` default / `; async; stackless;`
  later) — parsed exactly like `generator`/`assembler`: a `CaseEqual` identifier
  in the directive position, **not** a reserved word, so FPC keeps compiling
  `compiler.pas` (the keyword is never *used* there).
- Marker: **`await E`** — a new `AN_AWAIT` AST node, gated on `CurProcIsAsync`
  (so `await` stays a usable identifier outside async routines; an `await` outside
  async falls through to ordinary identifier lookup). Binds tightly like Python
  (`await f() + 1` ≡ `(await f()) + 1`); legal in expression *and* statement
  position (statement form parses a full — possibly void — call statement).

## Log
- 2026-06-16 — **Step #3 (stackless coroutine backend) DONE — all 4 targets,
  zero asm** (commit 05fa2a9). `; async; stackless;` compiles to a state-machine
  step function `function(self): Boolean`, reusing the stackless-**generator**
  transform wholesale: `SLHasYield` now detects `AN_AWAIT`; a new `SLLowerAwait`
  mirrors `SLLowerYield` minus the produced-value store (`await Stmt` runs Stmt,
  checkpoints locals, returns True = "resume me"; fall-off returns False = done).
  The ABI-rewrite + body-compile branch generalised to async (a `procedure`
  becomes the step function; v1 takes **no declared params** — state lives in
  persistent locals). `await` may be bare (`await;` = pure suspension) or wrap a
  statement. Eligibility = the same local rule as generators (await only at top
  level / for / while / if; try/case/etc. is a clear error) — this is what bounds
  transitive suspension **locally**, no whole-program analysis.
  - Driver: `lib/rtl/slsched.pas` (PXX-only) — `SLSpawn`/`SLRunUntilDone`
    round-robin the live set, resuming each coroutine one await-step per pass via
    an **indirect (proc-typed) call** to its stored step fn (possible now that
    procedural types exist — the original generator note "PXX can't call a stored
    fn-ptr with args" is obsolete). Spawn surface: the compiler-recognised
    `AsyncGo(@Body)` desugars to `SLSpawn(@Body, SlAlloc(instSize, ...))`
    (instance from slgen; instance layout SL_OFF_* shared with generators).
  - `test/test_async_sl.pas`: two stackless coroutines interleave at their await
    points, **byte-identical x86-64/i386/aarch64/arm32** (the no-asm claim).
    Validation fires for no-await / await-in-try / params / AsyncGo-on-non-async.
    Bootstrap + cross-bootstrap byte-identical (procs=917); `make test` +
    `test-i386/aarch64/arm32` green.
  - **Auto-selection (eligible→stackless else stackful) deliberately deferred**
    (matches the generator v3 decision); default stays stackful, `stackless`
    forces. v1 stackless async = no params, no result, ordinal/pointer locals
    only (same restrictions as the stackless generator). Follow-ups: params via
    instance slots (mirror the generator for-in arg store); a Task/Future for
    `await`-with-result (build-order #5); Nil Python `async def`/`await` shim
    (build-order #4) over `AsyncGo`/`SLRunUntilDone`.
- 2026-06-16 — **Warmup (build-order #1) DONE — configurable coroutine stack +
  overflow canary** (commit 2e54b14). `SpawnSized(entry, arg, stackBytes)` in
  `lib/rtl/scheduler.pas` runs a coroutine on a small heap stack (the RAM-cheap
  ESP path); `Spawn` now just calls it with the 64 KB `CO_STK` default. Every
  stack carries a `CO_CANARY` word at its low end, checked when the coroutine
  finishes — an overflow that reaches the base aborts with a message instead of
  silently corrupting the heap. Pure library (PXX-only), no compiler change.
  `test/test_costack.pas` (three workers on 8 KB stacks) runs byte-identical on
  x86-64/i386/aarch64/arm32.
- 2026-06-16 — **Step #2 (Pascal async surface) DONE — stackful** (commit
  429bf7f). `; async;` directive + `await` marker per the spelling above.
  `ProcIsAsync[]` + `CurProcIsAsync` (saved/restored alongside the generator body
  context). v1 backend is **stackful**: `await` is documentary — `AN_AWAIT`
  lowers straight to its operand in the IR (`IRLowerAST`), and the awaited call
  suspends on its own via the reactor / `CoYield`. The node is in place for the
  stackless backend to use as the split point. Validation: async ⊄ generator/
  assembler; `async stackless` errors (not implemented). `test/test_async.pas`
  (two async workers each `await` a suspending async helper) interleaves + ends
  on the cooperative scheduler. Bootstrap + cross-bootstrap byte-identical
  (procs=916); `make test` green.
  - Notes / non-blocking gotchas hit while testing (orthogonal to this work):
    `CoSleep(0)` arms a *disarmed* timerfd (it_value all-zero) → never fires;
    and a *single* coroutine that yields once then finishes hangs `RunUntilDone`
    (reproduces on the pre-change compiler too — a pre-existing scheduler edge
    case, not caused by the async surface). Multi-coroutine cases are fine.
  - **Next: step #3 — the stackless coroutine backend** (the hard part): the
    state-machine transform behind `; async; stackless;`, reusing the
    stackless-*generator* transform shape (`parser.inc` SL* helpers). `await`
    becomes the required local split marker; default stays stackful.
- 2026-06-16 — opened from the async-ergonomics design discussion. Key
  conclusions: stackful needs no keywords (a feature); `await` is required only
  for the stackless transform (bounds transitive suspension locally) but is
  useful as documentation on stackful; build in Pascal first, reuse in Nil
  Python; ESP can run stackful with small/configurable stacks, stackless is the
  RAM optimization. Sequenced after classes-on-cross
  (feature-cross-target-feature-parity) so ESP/embedded isn't fighting two new
  fronts at once.
