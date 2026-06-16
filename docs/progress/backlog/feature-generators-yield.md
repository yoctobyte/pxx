# Generators and `yield` (the coroutine on-ramp)

- **Type:** feature
- **Status:** backlog
- **Blocked-by:** feature-unified-heap-allocator
- **Opened:** 2026-06-16

## Why generators first

Generators are the gentle on-ramp to async/coroutines: a one-way, consumer-driven
producer (`yield v` → consumer pulls via `for x in g()`), simpler than symmetric
coroutines, immediately useful (iterators, lazy sequences, token streams), and
they exercise the same stack-switch machinery a scheduler would — with far less
runtime. Build this before the scheduler/reactor in feature-async-coroutines.

Library/user-only: FPC has no generators, so the FPC/PXX boundary keeps them out
of `compiler/` (see feature-fpc-vs-pxx-feature-boundary). No self-host constraint
on the feature itself.

## Design decision — BOTH lowerings, one surface, `; generator;` directive

We want **both** a stackful and a stackless implementation (decided 2026-06-16).
The **language surface is identical** for either — `; generator;`, `yield`,
`for x in g`, the iterator protocol — only the lowering differs. Implement the
iterator protocol + `for-in` ONCE; plug in two lowerings. `for-in` never cares
which strategy a generator used.

### Surface — a Pascal directive (not a Python `@decorator`)

`generator` is a routine directive, like `inline` / `cdecl` / `assembler`
(minimal lexer change — same machinery):

```pascal
function Squares(n: Integer): Integer; generator;            { auto strategy }
function Tokens: Integer; generator; stackless;              { force stackless }
function Walk(t: TTree): Integer; generator; stackful;       { force stackful  }
```

### Strategy selection

- `; generator;` alone → **auto**.
- `; generator; stackful;` / `; generator; stackless;` → forced.
- **Auto rule (documented, predictable):** stackless when every `yield` is in
  transformable control flow — top-level body, straightline / `for` / `while` /
  `if` — and no `yield` crosses a call boundary or sits in a `try`. Otherwise
  stackful. Force-`stackless` on an ineligible body → clear compile error.

### Two lowerings

- **Stackful:** the iterator wraps a coroutine (`CoSwitch` + a small heap stack).
  `yield` works anywhere. Shared with feature-async-coroutines.
- **Stackless:** the compiler transforms the body into a state-machine record
  (resume point + saved locals); no heap stack, restricted yield placement.
  Ideal for ESP32 (tiny RAM).

### Validation (the "complain" rules)

- `; generator;` but **no `yield`** in the body → error.
- `yield` **without** `; generator;` → error ("yield outside a generator").
- `yield` value type ≠ declared result type → error.
- `yield` inside `try`/`finally`/`except` → error in v1 (accepted restriction;
  also disqualifies stackless eligibility).

### Self-host

The `generator`/`yield` keywords + transform live in the compiler (FPC compiles
that source fine — it just never sees a `generator` *used* in `compiler.pas`).
FPC/PXX boundary: add the feature; never use it in `compiler/`.

## v1 lowering — stackful (reuse `CoSwitch`)

A generator is a coroutine with a constrained protocol. Build it on the same
per-target context-switch primitive that feature-async-coroutines needs:

```
TCoroCtx = record sp: Pointer; ... end;
procedure CoSwitch(var from: TCoroCtx; const to: TCoroCtx);  { the only asm }
```

- `yield v` saves the generator's value somewhere shared and `CoSwitch`es back to
  the consumer; `for x in g` `CoSwitch`es into the generator for the next value.
- A small heap stack per live generator (fixed, configurable, canary-guarded).
- **`yield` works anywhere** (loops, nested calls) — no transform restrictions.

Pro: minimal compiler work (no CPS/state-machine transform); the expensive part is
six small asm stubs (one per target — x86-64/i386/aarch64/arm32/riscv32/xtensa),
and the codegen already has inline asm + per-target encoders.

### Accepted restriction (v1)

**Forbid `yield` inside `try`/`finally`/`except`** with a clear compile error.
This sidesteps the exception-frame swap (PXX exceptions are setjmp-style with a
per-stack `BSS_EXC_TOP` chain; cross-stack `raise` would otherwise unwind the
wrong frames). Lift the restriction later, together with the coroutine work that
needs the full exc-top save/restore.

## Iterator protocol (do this generally)

Define a small iterator contract — e.g. `function Next(var v: T): Boolean` (or
`MoveNext`/`Current`). `for x in g` calls it until False. A generator is just one
implementation; make arrays / collections implement the same contract so `for-in`
becomes a general feature, not generator-specific. Two wins for one.

## Surface

```pascal
generator function Squares(n: Integer): Integer;
var i: Integer;
begin
  for i := 1 to n do yield i * i;
end;

var x: Integer;
for x in Squares(5) do writeln(x);   { 1 4 9 16 25 }
```

- New `yield` keyword (lexer/parser) — only legal in a `generator`-marked routine.
- `for <var> in <generator-call>` drives the iterator protocol.

## Stackless backend (second lowering — planned, not optional)

Transform a stackless-eligible generator into a state-machine record + iterator
(resume point + saved locals). No asm, no heap stack — ideal for ESP32 (tiny RAM).
Cost: `yield`-placement restrictions (top-level / simple loops, no yield across a
call boundary or in a `try`) and the transform itself. Behind
`; generator; stackless;` first, then folded into auto-selection. Same surface as
stackful — no grammar change to add it.

## Phasing

1. `CoSwitch` asm primitive (shared with feature-async-coroutines) on x86-64,
   then all six targets. Prove a two-context ping-pong; self-host fixedpoint
   holds.
2. **v1 surface + stackful backend:** `; generator;` directive + `yield` +
   iterator protocol + `for-in` + all validation rules (no-yield, yield-outside,
   type-mismatch, no-yield-in-try). Stackful lowering only.
3. Make arrays / collections implement the same iterator protocol (general
   `for-in`).
4. **v2 stackless backend** behind `; generator; stackless;` — the state-machine
   transform. Same surface.
5. **v3 auto-selection** (eligible → stackless, else stackful); keep the force
   overrides.
6. (Later) lift the `yield`-in-`try` restriction together with the coroutine
   exc-top save/restore work.

## Acceptance

`for x in g()` over a `generator` routine yields the correct sequence, suspends/
resumes across loop iterations, frees its stack at exhaustion; `yield` inside a
`try` is a clear compile error; self-host fixedpoint + cross-bootstrap unaffected
(library-only feature).
