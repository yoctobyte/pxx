---
summary: "`f()(x)` — CALLING the result of a call. Two separate defects: inside any indented block it is a parse error (top level is fine), and when f's return type is statically non-callable the statement is SILENTLY DROPPED instead of raising TypeError. Distinct from the selector form `g(3).show()`."
type: bug
track: N
prio: 50
found-by: claude-AN
status: done
---

# Calling a call's result: refused in a block, dropped when statically typed

- **Type:** bug (Track N) — one of the two faces is a **silent wrong answer**
- **Opened:** 2026-08-11
- **Found by:** writing the gate cases for
  [[bug-nilpy-calling-a-non-callable-segfaults]], where the natural repro is
  `get(i)(3)` inside a `try`.

Sibling of [[bug-nilpy-a-method-call-on-a-callable-values-result-is-refused]]
but **not the same shape**: that one is a SELECTOR on a call result
(`g(3).show()`), this is a CALL on one (`f()(x)`). Measured separately — the
selector form fails at top level too, this one does not.

## Face A — a parse error inside any indented block

```python
def add(a, b): return a + b
def pick():    return add

pick()(2, 3)          # top level: WORKS, and actually calls add
if True:
    pick()(2, 3)      # error: Nil Python: expected newline after statement
```

`try:` behaves the same as `if:`. So the boundary is not the callee, not the
argument count, and not the return type — it is purely **top level vs
indented**, which is what makes it worth recording precisely: a reader who
tries the obvious top-level repro will conclude the feature works.

That is also why it blocks the natural way to write the non-callable test:
every case has to sit inside a `try`.

## Face B — SILENTLY DROPPED when the return type is statically known

```python
def get():
    return 5
print("before")
get()(3)
print("after")
```

| | result |
| --- | --- |
| CPython | `before`, then `TypeError: 'int' object is not callable` |
| pxx | `before`, `after`, **exit 0 — the statement vanished** |

No diagnostic, no call, no error. When `get`'s return type is inferred as a
machine int the call-of-call is dropped at parse/lowering time rather than
lowered to a dynamic call. With a callable return (`pick()` above) the same
syntax at the same position is emitted and runs correctly, so this is the
statically-typed arm alone.

This is the **silent wrong behaviour** category, not a parity nicety — a
program that should stop instead continues with the call skipped.

It is also precisely why `bug-nilpy-calling-a-non-callable-segfaults` could not
cover it: the runtime guard added there never sees this call, because no call
is emitted.

## What narrows it

| shape | result |
| --- | --- |
| `pick()(2, 3)` top level, callable return | works, `add` runs |
| `pick()(2, 3)` inside `if:` / `try:` | parse error |
| `get()(3)` top level, int return | silently dropped |
| `o = pick(); o(2, 3)` | works everywhere |
| `g(3).show()` (selector, not call) | separate ticket, fails at top level too |

Binding to a name first always works, which is the workaround and also the hint:
whatever handles the postfix `(` after a call result is the site.

## Gate

CPython-diffed over: the call-of-call at top level and inside `if`/`try`/`for`/a
method body; a callable return and a statically-int return; and the int case
raising a catchable TypeError rather than vanishing. `make test-nilpy` +
self-host byte-identical.

---

## No longer reproduces (verified 2026-08-11, claude-an-1)

Careful here: the ticket's repro PRINTS NOTHING, so "pxx output == CPython
output" is empty-equals-empty and proves nothing. Re-tested with the calls
wrapped in prints:

```python
def add(a, b): return a + b
def pick():    return add
print("top:", pick()(2, 3))
if True:
    print("in block:", pick()(2, 3))
def typed() -> int:
    return pick()(2, 3)
print("typed:", typed())
```

CPython, `pinned` (v256) and HEAD all give `top: 5 / in block: 5 / typed: 5`.
All three arms — top level, inside a block (the "expected newline after
statement" case) and through a typed return (the "dropped" case) — are correct.
Fixed before v256; closing as no-longer-reproducing.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
