---
track: N
prio: 70
type: bug
summary: "`f() and x` / `f() or x` call f() TWICE — the left operand's side effects are duplicated. Silent, no error. Root cause read out of PyMakeBoolOpValue: the same AST node is used as both the condition and an arm, and the AST is a TREE"
---

# `and` / `or` evaluate the LEFT operand twice

- **Type:** bug (NilPy — SILENT duplicated side effects) — **Track N**
- **Found:** 2026-08-02 by a differential sweep against the CPython oracle
  (`tools/pydiff.py`). Found in the same sweep as
  [[bug-nilpy-and-or-of-two-different-classes-reinterprets-one-as-the-other]],
  which is a *different* bug in the *same* function and is already fixed.

## Measured — decisive one-liner, no classes, no containers

```python
n = 0
def bump():
    global n
    n += 1
    return 0
x = bump() and 5
print("n =", n)          # CPython: n = 1        pxx: n = 2
```

`bump()` runs twice. Nothing is printed wrong, nothing crashes; the only
evidence is the side effect happening one extra time.

The tracing form, which shows it is the LEFT operand and that short-circuiting
is otherwise correct:

```python
def side(v, tag):
    print("eval", tag)
    return v

side(False, "a") and side(True, "b")
# CPython: eval a
# pxx    : eval a / eval a          <- `b` correctly never runs

side(True, "c") or side(False, "d")
# CPython: eval c
# pxx    : eval c / eval c          <- `d` correctly never runs
```

So the short-circuit *decision* is right — the skipped operand is genuinely
skipped. What is wrong is that the operand that IS taken is emitted twice.

## Root cause — read out of the source, not inferred from the symptom

`PyMakeBoolOpValue` (`compiler/pyparser.inc`) lowers `a or b` to a ternary:

```pascal
condNode := PyMakeTruthy(a);
if isOr then begin thenNode := a; elseNode := b; end
else begin thenNode := b; elseNode := a; end;
...
ASTLeft[node] := condNode;
ASTRight[node] := pairNode;      { PAIR(thenNode, elseNode) }
```

Node `a` is used **twice**: once wrapped inside `condNode`, and once as an arm
(`thenNode` for `or`, `elseNode` for `and`). `b` is used once, which is exactly
why only the left operand duplicates.

`PyEvalOnce`'s own doc comment in the same file states the rule this violates:

> the AST is a TREE, so a node referenced twice is EMITTED twice — a call
> receiver in a chain ran its call once per link

This is that identical failure, in the boolean-operator lowering.

## Why the obvious fix is NOT correct — measure before applying it

The one-line change is `a := PyEvalOnce(a)` at the top of `PyMakeBoolOpValue`.
**Do not land that without handling the following**, which would trade this
silent bug for a different silent bug:

`PyEvalOnce` binds the value through `PyHoistStmt`, which queues the assignment
onto `PyHoistHead` — a **statement-level** hoist. For a top-level
`x = f() or g()` that is fine: `f()` has to be evaluated first anyway. But
nested inside another short-circuit it is not:

```python
x = a and (b() or c())
```

`b()` is the left operand of the inner `or`, so hoisting it to the top of the
statement evaluates `b()` **even when `a` is falsy** — breaking the outer
short-circuit. Today `b()` is at least still inside the conditional region (it
is merely emitted twice there), so the outer short-circuit does hold. A
statement-level hoist would leak the side effect out of it.

The same applies to any position where the boolop is not unconditionally
evaluated: a comprehension's `if` filter, a lambda body, a ternary arm, the
right operand of another `and`/`or`.

## Shape of a fix that is actually safe

The value has to be bound **where `a` currently sits**, not at statement level —
i.e. an assignment usable as an EXPRESSION, so the condition becomes
`truthy($t := a)` and both arms read `$t`. There is no walrus / expression-assign
node in the NilPy frontend today (grepped: no `tkColonEq`, no expression-assign
AST node), so this needs either:

- a new AST node for "assign and yield the value" — that is a **shared-internals
  change and therefore a Track A ticket**, not a Track N edit; or
- a `PyEvalOnce` variant that hoists into the nearest **enclosing conditional
  region** rather than the statement, which requires knowing that region — the
  frontend does not track it today; or
- lowering `a or b` to a form where the condition consumes the value directly
  (a dedicated AN node meaning "test this, keep it if truthy, else evaluate the
  other arm"), which is the least invasive of the three and keeps everything
  inside the existing ternary machinery.

Recommend the third. Whichever is chosen, the nested case above is a required
gate line, not an optional one.

## Scope — where this actually bites

The Python idioms that put a call on the left of a boolop are common and the
duplicated call is usually invisible:

```python
val = cache.pop(k) or compute()      # pops twice
line = fh.readline() or "<eof>"      # consumes two lines
ok   = record() and commit()         # records twice
```

A pure function on the left is harmless, which is why this survived: the sweep
only saw it because the probe printed from inside the operand.

## Gate

A `.npy` diffed against CPython covering: a counter incremented from the left
operand of `and` and of `or` (both truthy and falsy), the tracing form above,
the NESTED case `a and (b() or c())` with `a` falsy — asserting `b()` does not
run at all — the same nested shape inside a comprehension filter and inside a
lambda, and a right-operand call to confirm it is still evaluated exactly once
when reached and zero times when short-circuited.
