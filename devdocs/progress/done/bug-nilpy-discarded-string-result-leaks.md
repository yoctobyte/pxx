---
track: N
prio: 50
type: bug
---

# A call whose managed-string result is DISCARDED leaks it

```python
def flabel(v: int) -> str:
    return str(v)

while i < n:
    flabel(7)          # result dropped
    i = i + 1
```

RSS slope, 20k vs 320k iterations: **952 KB -> 10296 KB**. Binding the same
result to a name is flat (`s = flabel(7)`), and so is consuming it
(`len(flabel(7))`). Only the DROPPED result leaks — the callee hands back a
handle at +1 and nothing ever releases it, because there is no store to carry
the ownership.

Affects plain defs and methods alike, so it is not the method-vs-def divergence
[[bug-nilpy-method-returning-a-fresh-string-leaks]] fixed (that one was a double
RETAIN at the store; this one is a missing RELEASE where there is no store).
Both were measured in the same session; this one was left because it is a
different mechanism in a different place.

~32 bytes an iteration, silent. The shape is ordinary: a method called for its
side effect that happens to return a string (`buf.append_line(...)` returning
the new text, a logger returning what it logged).

## Recon 2026-07-30 — why the obvious hook does not work

Picked up and put back down deliberately; recording the dead ends so the next
attempt does not re-walk them.

- `IRDiscardValue` (ir.inc) is the statement-level "value thrown away" hook, but
  its wrapping half is `CProgramMode` only and it wraps into a plain temp. A
  hidden MANAGED temp does not fix the slope either: its release happens at
  SCOPE exit, so a 320k-iteration loop inside one routine still accumulates
  320k handles before anything is freed. The release has to be per-statement.
- There is no Pascal-callable string release to emit a call to:
  `AnsiStrReleaseAddr` is a raw code stub in ir_codegen.inc (handle in rax), not
  a Proc, so ir.inc cannot `IRAppendCall` it.
- That leaves two routes, and picking between them is the first real decision:
  (a) a new IR op (`IR_STR_DROP`: evaluate operand to rax, call the stub) —
      clean, but every backend must implement it or a cross-compiled NilPy
      program breaks, so it is not the small change it looks like;
  (b) a pylib `procedure pystr_drop(s: AnsiString)` with a BY-VALUE managed
      parameter, whose scope exit does the release — no new op, but it depends
      on whether the by-value managed-param convention MOVES the caller's owned
      handle or retains it. Measure that first (today's
      bug-nilpy-method-returning-a-fresh-string-leaks work says call results are
      moved into stores; the argument path was not checked).

## Attempt 2026-07-30 — IRDiscardValue is NOT the hook (measured, reverted)

Tried and REVERTED, so the next attempt does not repeat it. The idea was sound
and needs no new IR op: store the discarded result into a hidden temp belonging
to that SITE, because the managed store releases the slot's previous value
before taking the new one — so a loop keeps at most one handle alive and the
scope-exit release frees the last.

The hook was wrong. `IRDiscardValue` (ir.inc), which the AN_BLOCK statement-list
arm calls for every item, looked like the place; a branch there for
`PyProgramMode` + `tyAnsiString` + a call kind, placed BEFORE
`IRMarkStatementNode` and returning, compiled and self-hosted byte-identical —
and changed nothing. The RSS slope was identical (952 KB -> 10296 KB), and
`PXXDBG=a.ir:<routine>` still shows the call with `ival=1`, i.e. something ELSE
marks a NilPy statement call as a statement.

So the first job for the next attempt is to find who sets `IRIVal := 1` on a
NilPy statement-level call — it is not `IRDiscardValue`. Put the store there
instead, and keep the "before the mark, then return" discipline: a store is
itself a statement root that drags its operand tree in, so marking the call as a
statement TOO would emit it twice.

## Where to look

The statement-expression path: when an expression statement's value is a managed
type and is not stored anywhere, it needs a release after evaluation — the same
scope-exit treatment a hidden temp gets. `IRIVal[node] := 1` marks a call
emitted for effect (see IRAppendCall's callers); that marker is the natural
place to decide the result needs dropping.

Check the same shape for a discarded OBJECT result and a discarded variant while
there — an object result carries the callee's return-retain
([[bug-nilpy-returning-a-construction-leaks-one-ref]]), so it should leak
identically.

## Gate

`make test-nilpy` + self-host byte-identical, plus RSS-slope pairs for a
discarded string result from a def, from a method, and a discarded object
result — all flat.

## Log
- 2026-07-30 — resolved, commit c67dfd9c0.
