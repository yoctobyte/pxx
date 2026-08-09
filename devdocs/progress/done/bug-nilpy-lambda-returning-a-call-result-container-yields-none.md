---
prio: 50
track: N
type: bug
blocked-by: []
status: done
---

# A lambda whose body is a CALL returning a container yields None

- **Type:** bug (NilPy, **silent wrong value**) — **Track N**
- **Found:** 2026-08-09 by a differential sweep of type conversions.
- **Owner:** agent-AN

```python
f = lambda: list("abc")
print(f())              # CPython ['a', 'b', 'c']    pxx None

g = lambda x: sorted(x)
print(g("cab"))         # CPython ['a', 'b', 'c']    pxx None
```

`list("abc")` written as a STATEMENT is correct. Only through a lambda is it
None, and silently.

## Measured boundary

| lambda body | result |
| --- | --- |
| `[1, 2]`, `(1, 2)` — container LITERAL | correct |
| `"s"`, `7`, `len(s)`, `str(1)`, `abs(-1)` — scalar/string | correct |
| `[1] + [2]` — a binop | correct |
| `x[0]`, `x + 1` — on a parameter | correct |
| **`list(s)`, `tuple(s)`, `sorted(s)`** | **None** |
| **`mk()` where a user def returns a list** | **None** |

So it is exactly: the body is an `AN_CALL` whose result is `tyClass`.

## Cause — deliberate, and this is the third case it caught

`PyCompileLambdaBody` refuses to return a `tyClass`/`tyRecord` value at all.
That refusal is not a bug: it exists because `lambda s: log.append(s)` returns
the CAPTURED list itself, and boxing that into `$pyresult` for a caller who
discards it drove the captured object to refcount 0 and freed it under the
enclosing scope (measured previously with `-dPXX_OBJTRACE`: 4 retains / 5
releases). It is the ARC gap
[[bug-nilpy-bound-fn-closure-objects-are-never-freed]].

`PyLambdaResultIsOwnedTemp` carves a hole for the case that is provably safe: an
`AN_IDENT` of a body-local, i.e. a container LITERAL's hoist temp, which owns
its construction ref. That carve-out was added for
`bug-nilpy-a-tuple-returned-from-a-lambda-becomes-a-list`.

A CALL result is the **third** case and is currently on the wrong side of the
line. `list(s)` and `sorted(s)` build a fresh object and own it exactly as a
literal does — they are not aliases of anything — but the predicate excludes
every `AN_CALL` because a METHOD call might return `Self`.

## The two routes

1. **Widen the carve-out to provably-fresh calls.** The distinction that matters
   is fresh-vs-alias, not call-vs-ident. A call to a pylib CONSTRUCTOR
   (`list`/`tuple`/`sorted`/`set`/`dict`/`bytes`…) always builds a new object;
   a method call on a captured receiver may not. That means an allowlist by
   proc, which the current predicate deliberately avoided ("structural, not by
   name") — but it avoided names for a different question (local vs capture),
   so it is not the same trade.
   **A user def returning a list is NOT safe to include**: the def may return a
   captured global, which is the aliasing case again.
2. **Fix the ARC gap** and drop the refusal entirely. The right answer, and the
   bigger one.

## Verify with the instrument, not by reasoning

Whichever route: check with `-dPXX_OBJTRACE` that retains and releases BALANCE
for the widened shape, the way the previous session did (scalar and managed
string balance 2/2; the aliasing case was 4/5). This is a refcount change, so
"the test passes" is not evidence — a double free shows up later and elsewhere.

## Gate
`.npy` diffed against CPython: `lambda: list(s)`, `tuple(s)`, `sorted(s)`, a
lambda taking a parameter, and the shapes that already work (literal, scalar,
binop, index) as controls — plus `lambda s: log.append(s)` on a CAPTURED list
still behaving, with an `-dPXX_OBJTRACE` balance check on it.

## PARTLY FIXED 2026-08-09 — and half of this ticket was never a lambda bug

### What landed

Route 1, as recommended. `PyLambdaResultIsOwnedTemp` now also accepts an
`AN_CALL` to a pylib **constructor** builtin — `list`, `tuple`, `dict`, `bytes`,
`bytearray`, `reversed` (pylib) and `sorted` (pyeval, which is where it lives
because it takes a key callback). Their bodies were READ, not assumed from
Python semantics: each does `r := TPyList.Create` (or the bytes/dict twin) and
fills a NEW object, so the value owns its construction ref exactly as a
literal's hoist temp does. `bytes(b)` was the one worth checking — it could have
returned its argument, and it copies.

Matched by name **and declaring unit**. The name alone is not enough: a user
`def list(...)` shadows by argument fit
(`project_findproc_by_name_ignores_overloads`), and accepting it would hand back
an alias under a builtin's name — the exact case the refusal exists for. A user
def returning a container therefore stays excluded, as the ticket required.

### Worse than reported: the refusal emits NO exit at all

The ticket says the value is None. `PXXDBG=a.ir` on the lifted body shows why
that undersells it:

```
$pylam1:  call 1090(...)  ival=1    <- the call, as a statement
          block                     <- and that is the whole proc
```

No store to `$pyresult`, no `AN_EXIT`. The caller reads an **uninitialised
slot** — None if it happens to be zero, garbage otherwise. So the same defect
produced a silent wrong value in one program and a SIGSEGV in the next.

### The refcount check the ticket demanded, done with the instrument

Not "the test passes":

- `mk = lambda x: list(x)` called **200 000** times, result consumed:
  correct total, **RSS flat at 1.5 MB**, exit 0. No leak and no double free —
  a scaling curve, not a single run.
- The aliasing control `add = lambda s: log.append(s)` over 100 000 calls:
  still correct, stable. The carve-out did not widen to it.
- `-dPXX_OBJTRACE` on the mixed program shows the fresh objects reaching
  refcount 0 and being freed, with the captured list untouched.

### The other half of this ticket is a DIFFERENT bug

`lambda x: sorted(x)` and `lambda x: tuple(x)` still fail — and the lambda has
nothing to do with it. Varying the shape:

```
def g(x): return tuple(x)   -> SIGSEGV        (also on `pinned`)
for x in ["cab"]: tuple(x)  -> SIGSEGV        (no def, no lambda)
```

`tuple(<variant>)` binds the `TPyList` overload and inserts an unchecked
`pyvarobj` unwrap, so a variant holding a STRING is reinterpreted as an object
pointer. `list` escapes only because it is the one builtin in the group with a
`Variant` overload. Five builtins crash this way. Filed with the full table and
the IR evidence as
[[bug-nilpy-a-variant-argument-binds-a-class-overload-and-is-unwrapped-unchecked]]
(prio 60 — it is a segfault from ordinary Python, and one hole rather than five
bugs).

This ticket is therefore **CLOSED for the lambda defect it names**; the two rows
it listed that still fail are tracked there. Splitting them rather than leaving
one ticket half-red is the honest bookkeeping: nothing about the lambda lowering
can fix an argument-lowering hole.

### Gate

- `test/test_nilpy_lambda_container_result.npy` EXTENDED (rather than a
  near-duplicate new file — it is the sibling ticket's test and already pins the
  aliasing case): a call-result body through a one-parameter and a
  zero-parameter lifted lambda, the result consumed, repeated across
  iterations, plus a user-def-returning-a-container control proving the
  exclusion is still an exclusion and not a crash. Matches CPython byte for
  byte; both Makefile sites updated.
- Self-host fixedpoint byte-identical; `tools/gate.sh quick` GREEN.

## Log
- 2026-08-09 — resolved, commit 943784977.
