# Generators

A generator is a routine that produces a sequence lazily: each `yield E` hands a
value to the consumer and suspends; the consumer pulls the next value with
`for x in g(args)`. This is a PXX extension (FPC has no generators), so it lives
behind a routine directive and never appears in `compiler.pas` itself.

## Surface

Mark a **function** `generator`. Its declared result type is the *element* type;
`yield` produces values of that type:

```pascal
function Squares(n: Integer): Integer; generator;
var i: Integer;
begin
  for i := 1 to n do yield i * i;
end;

var x: Integer;
begin
  for x in Squares(5) do writeln(x);   { 1 4 9 16 25 }
end.
```

- A generator must be a `function` (the result type is the yielded type).
- `yield E` is only legal inside a generator body; `E`'s type must match the
  result type.
- `for v in Gen(args)` drives the iterator to exhaustion. Up to 4 arguments.
- The loop interoperates with `break`/`continue`/`exit` as usual.

The same surface drives **both** lowerings below — consumer code never cares
which strategy a generator used.

## Two backends

```pascal
function F(…): T; generator;            { stackful (default today)    }
function F(…): T; generator; stackful;  { force stackful              }
function F(…): T; generator; stackless; { force stackless             }
```

### Stackful

The body runs as a coroutine on a small heap stack, switched in/out by a tiny
context-switch primitive. `yield` works **anywhere** — inside nested loops,
helper-call frames, etc. — with no transform restrictions. Requires
`uses coroutine;`.

Today the stackful backend is **x86-64 only** (the context switch is asm; ports
to the other targets are pending).

### Stackless

The body is **transformed** into a state machine — a step function plus a heap
instance holding the resume point and the persistent locals. No coroutine stack,
no context switch, **no per-target assembly**, so it runs on **every** target
(verified x86-64 + i386 + arm32 + aarch64). Ideal for tiny-RAM embedded targets
(ESP32). Requires `uses slgen;`.

```pascal
function Squares(n: Integer): Integer; generator; stackless;
var i: Integer;
begin
  for i := 1 to n do yield i * i;
end;
```

Restrictions (enforced — a violation is a clear compile error):

- `yield` may appear only at the top level of the body or inside `for` / `while`
  / `if`. `yield` in `case` / `repeat` / `with`, or in a loop/`if` **condition**
  or a `for` bound, is rejected.
- `yield` inside `try`/`except`/`finally` is rejected (a **permanent** stackless
  restriction — the exception frame is on the transient step stack).
- Persisted locals/parameters must be **ordinal- or pointer-sized**. Managed
  string, dynamic-array, and record locals that live across a `yield` are not
  supported on this backend. Use the stackful backend (a real stack carries
  managed locals with normal ARC), or frozen strings, for those.

### Choosing

Bare `; generator;` currently uses the stackful backend. Automatic
stackful/stackless selection (stackless when eligible, else stackful) is planned;
until then use the explicit `stackful` / `stackless` directive to force one.

## Validation summary

| Condition | Result |
| --- | --- |
| `generator` on a non-function | error |
| `yield` outside a generator | error |
| `yield` type ≠ result type | error |
| generator with no `yield` | error |
| `stackless` without `generator` | error |
| `yield` in `try` | error (both backends) |
| `stackless` with `yield` in `case`/`repeat`/`with`/a condition | error |
| `stackless` with a managed local across `yield` | error |
| generator with > 4 parameters | error |
