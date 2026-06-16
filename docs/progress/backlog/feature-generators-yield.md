# Generators and `yield` (the coroutine on-ramp)

- **Type:** feature
- **Status:** backlog
- **Blocked-by:** feature-unified-heap-allocator (heap stack per generator)
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

## Recommended approach — stackful (reuse `CoSwitch`)

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

## Alternative — stackless restricted (note for embedded)

Transform a restricted generator into a state-machine record + iterator (resume
point + saved locals). No asm, no heap stack — ideal for ESP32 (tiny RAM), at the
cost of `yield`-placement restrictions (top-level / simple loops only) and more
compiler work. Keep as the embedded-RAM option; not the MVP.

## Phasing

1. `CoSwitch` asm primitive (shared with feature-async-coroutines) on one target,
   then all six. Prove a two-context ping-pong; self-host fixedpoint holds.
2. `generator` routines + `yield` + the iterator protocol + `for-in`.
3. Make arrays/collections implement the iterator protocol.
4. (Later) lift the `try` restriction; (later) stackless variant for embedded.

## Acceptance

`for x in g()` over a `generator` routine yields the correct sequence, suspends/
resumes across loop iterations, frees its stack at exhaustion; `yield` inside a
`try` is a clear compile error; self-host fixedpoint + cross-bootstrap unaffected
(library-only feature).
