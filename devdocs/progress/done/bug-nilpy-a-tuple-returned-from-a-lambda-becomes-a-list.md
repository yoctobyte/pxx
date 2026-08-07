---
track: N
prio: 50
type: bug
summary: "NilPy: a tuple literal returned from a lambda degrades to a list — `(lambda x: (x, x+1))(3)` prints [3, 4] and type().__name__ says 'list', while the identical expression returned from a def stays a tuple"
status: done
owner: claude-A-N
---

# A tuple returned from a lambda becomes a list

- **Type:** bug (silent wrong type) — **Track N**
- **Found:** 2026-08-07, bughunting with `tools/pydiff.py`.

## Measured (self-hosted fixedpoint at `8f1852f27`)

```python
t = (1, 2)
print(t)                        # CPython (1, 2)   pxx (1, 2)   agrees

def g(x):
    return (x, x + 1)
print(g(3))                     # CPython (3, 4)   pxx (3, 4)   agrees

f = lambda x: (x, x + 1)
print(f(3))                     # CPython (3, 4)   pxx [3, 4]   WRONG

print(type(f(3)).__name__, type(g(3)).__name__, type(t).__name__)
# CPython: tuple tuple tuple
# pxx    : list  tuple tuple
```

So the tuple tag survives a bare literal and a `def` return, and is lost only
through the **lambda** return path.

## Why this is a bug and not a documented divergence

`devdocs/dev/nilpy-semantics-divergences.md` accepts that a NilPy tuple is
mutable, on the ground that no working CPython program can observe it, and
states that *"everything else about a tuple is already CPython-exact:
`type(t).__name__`, `isinstance(t, tuple)`, …"*. This case is on the wrong side
of that line, by that page's own worked example: printing a returned pair and
branching on `type(...).__name__` / `isinstance(..., tuple)` are things ordinary
working CPython code does, and here they answer differently depending on whether
the producer was a `def` or a lambda. That doc's claim needs narrowing once this
is fixed, or amending if it is not.

Related but distinct — that one is about the three container types being
indistinguishable in general, this one is a tag lost on one specific path:
[[bug-nilpy-list-tuple-and-set-are-indistinguishable-to-isinstance]].

## Not yet investigated

Whether the lambda **body-compile** path (`PyCompileLambdaBody` / the lifted
`$pylamN` proc in `compiler/pyparser.inc`) builds the literal through a
different constructor than the statement path, or whether the tag is lost when
the variant result crosses the bound-fn return convention. Measure both before
concluding — do not reason it out.

## Gate

Per-fix loop. A `.npy` test asserting `type(...).__name__` and `print()` for a
tuple literal returned from a lambda, from a def, and bound directly — plus
`isinstance(..., tuple)` — diffed against CPython with `tools/pydiff.py`.

## 2026-08-07 — fixed, and it was TWO defects, one per lowering

The filed repro showed a tuple becoming a list. Probing the *other* lambda
lowering first — before touching anything — turned up a second, worse defect
in the same expression:

```python
def idn(v): return v
f = lambda x: (x, x + 1)          # no call in body -> INTERPRETED
g = lambda x: (idn(x), x + 1)     # call in body    -> LIFTED
```

| | interpreted | lifted |
| --- | --- | --- |
| before | `[3, 4]`, type `list` | **`None`** |
| after | `(3, 4)`, type `tuple` | `(3, 4)`, type `tuple` |

The lifted path returned None for **any** container literal, list included —
so this was never tuple-specific, and the filed title undersold it.

### Interpreted path

`pyeval.pas` builds `(a, b, …)` as a bare `TPyList` and never stamped its kind.
`PYSEQ_LIST` is 0, so the tuple defaulted to a list. One line: `li.FKind :=
PYSEQ_TUPLE`. The compiled lowering had always stamped it (`pylist_mark_tuple`);
only the interpreter's own parser did not — which is why a tuple's display
depended on whether its lambda happened to contain a call.

### Lifted path

`PyCompileLambdaBody` refuses to wrap a `tyClass`/`tyRecord` result in the
`AN_EXIT` that stores it to `$pyresult`, so such a body is evaluated for effect
and answers None. That refusal is deliberate and documented in place: it exists
for `lambda s: log.append(s)`, whose result is the CAPTURED list, where boxing
it into `$pyresult` and letting a discarding caller release it drove the
captured object to refcount 0 — the ARC gap
[[bug-nilpy-bound-fn-closure-objects-are-never-freed]].

But a container **literal** is the opposite case. Its lowering hoists
`__py_lit_N := <new>` and hands back a read of that temp, and that temp OWNS the
construction ref (`PyParseListLiteralT`'s own note) — there is no second owner
to unbalance. `PyLambdaResultIsOwnedTemp` carves exactly that back out:
structurally, an `AN_IDENT` of a LOCAL allocated inside this body's scope. A
capture arrives as a *parameter* and stays excluded, which is the aliasing case;
a method-call result is an `AN_CALL` and stays excluded too. Deliberately not a
name-prefix test on `__py_lit_`/`__py_tup_` — the ownership question is
structural, and matching hidden-name stems would silently include the next temp
someone adds.

**The ARC case is untouched by construction** — `log.append(s)` is an `AN_CALL`,
which the predicate rejects — and is pinned in the test with the repeated-call
and many-fresh-containers shapes besides.

### Gate

`make compiler/pascal26` (fixedpoint, converged 1 round) + `tools/gate.sh quick`
GREEN. `test_nilpy_lambda_container_result.npy` added, covering both lowerings,
`type().__name__`, the equivalent `def` (unchanged), and the aliased-capture
shape; diffed against CPython. No re-pin: the compiler does not `use` pyeval.

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.
