---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`min(xs, key=f)` where f is a NAME holding a callable raises `TypeError: expected a number, got object` — the two-argument numeric min/max overload is picked and compares the list against the function. `key=<def name>` and `key=lambda ...` both work, because those are pointer-typed nodes; only a callable held in a VARIABLE (any kind — a plain def, a bound method) loses"
status: done
owner: claude-AN
---

# `min(xs, key=f)` picks the numeric overload when the key is in a variable

- **Type:** bug (NilPy, wrong overload → runtime TypeError) — **Track N**
- **Found:** 2026-08-13, sweeping the callable representations while fixing
  [[bug-nilpy-map-over-a-bound-method-segfaults]]. Not caused by it: the
  **pinned** binary fails identically, which is the control that removes the
  variable rather than renaming it.

```python
def pk(x):
    return -x

f = pk
print(min([3, 1, 2], key=f))     # CPython 3
                                 # pxx TypeError: expected a number, got object
```

## The boundary

| spelling | result |
| --- | --- |
| `min(xs, key=pk)` — a bare def NAME | works |
| `min(xs, key=lambda x: -x)` | works |
| `min(xs, key=f)` where `f = pk` | **TypeError: expected a number, got object** |
| `min(xs, key=obj.method)` | same TypeError |
| `max(...)` in every row above | same as min |
| `sorted(xs, key=f)` | works |

The two that work are POINTER-typed AST nodes (an `AN_PROCADDR` for the name, a
lifted proc for the lambda). A callable held in a variable is a 16-byte VARIANT,
and that is what changes the answer.

`sorted` is the control that says the runtime side is fine: its overloads all
take `key: Pointer`, so there is no competing candidate, and a variant argument
is coerced by the generic Pointer-parameter path (`pyvar_callable_ptr`). `min`
and `max` also have `min(a, b)` numeric overloads — and the error message is
that overload comparing the LIST against the FUNCTION, so the pick, not the
call, is what went wrong.

## Where to look

Overload selection for a call with a `key=` keyword: `PyPromoteProcOverloadByKwAt`
promotes to a sibling that declares the named parameter, so the question is what
re-picks afterwards on ARGUMENT TYPES — a variant argument evidently matches the
`min(a: Variant; b: Variant)` candidate better than the `key: Pointer` one, and
the coercion that would make the Pointer candidate fit (parser.inc's
variant→`pyvar_callable_ptr` rewrite) only runs AFTER a proc has been chosen.

Related family, same root shape: a callable VALUE is a variant, and every place
that decides something by static type has to know it can become a pointer
([[project_nilpy_callable_has_three_representations]]).

## Gate

A `.npy` diffed against CPython: every row of the table above for both `min` and
`max`, plus `key=` holding a lambda in a variable, and `sorted` kept in the same
file as the control.

## 2026-08-13 — FIXED at the meaning, not at the resolver

The wrong pick is real, but widening overload resolution to prefer a
`key: Pointer` candidate over an exact `b: Variant` one is a Track A change with
a blast radius far past this bug. The observation that makes it unnecessary:
**comparing a function is a TypeError in CPython too**, so a callable second
argument to `min`/`max` can only ever have meant the key form. pylib's
two-argument `min`/`max` now answer it directly (`PyMinMaxByKey`), which is also
the ONE place both receiver shapes arrive at — a static list boxed on the way in,
and a variant container.

`PyVarIsCallable` is the callable test: tags 8/9/10/12, i.e. exactly the set
`PyVarTypeName` already answers 'method'/'function' for, so "callable" means the
same thing in both places.

**The layering needed one bridge.** pylib is the lower unit and cannot see
pyeval's `PyCallKey1`, so it could only invoke a bound PAIR itself — a lambda
held in a variable is a pyeval CLOSURE, and `max(xs, key=h)` answered 3 where
CPython says 1 (every key came back the same, so the first element won). pyeval
already publishes `PyCallKey1` into `PyIterCallHook`… but only from
`pymap_iter`/`pyfilter_iter`, i.e. only while a map cursor happened to be alive.
It is now installed in pyeval's `initialization`, which is where a hook meant to
be available for the whole run belongs, and `PyCallKeyVar` routes every non-pair
shape through it.

### Gate

`test/test_nilpy_min_max_key_in_a_variable.npy` + `.expected` from CPython,
wired into `make test-nilpy`: `key=` as a def NAME, an inline lambda, a def in a
variable, a lambda in a variable, a bound method in a variable, an inline bound
method, over a static list and over a VARIANT container, for both `min` and
`max` — plus `sorted` with the same key and the plain numeric/string forms as
controls, so a fix cannot trade the 2-argument min for the key form.
`make test-nilpy` green, `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
