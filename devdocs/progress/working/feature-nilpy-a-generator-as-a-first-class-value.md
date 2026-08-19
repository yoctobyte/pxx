---
track: N
prio: 55
type: feature
status: backlog
---

# A Nil Python generator can only be consumed by a `for`, never held as a value

Generators landed in [[feature-nilpy-yield-outside-a-for-loop]] and cover the
shape the third-party corpus is made of: a `def` or method that yields,
consumed directly by a `for` over the CALL —

```python
for x in gen(args): ...
for t in obj.gen(args): ...
for token in Base.__iter__(self): ...
```

Every other way Python touches a generator is unsupported:

```python
g = gen()               # a generator OBJECT
list(gen())             # consumed by a builtin
next(g)                 # the iterator protocol by hand
other(gen())            # passed as an argument
for t in some_object:   # iteration through __iter__, not through a call
```

**These are compile ERRORS today, not wrong answers** — the step ABI injects a
hidden `__genself` parameter, so a source-level call never matches arity. That
is the good failure mode and it should stay: whatever replaces it must not
quietly start calling a step function.

## Why it is not just more parsing

The desugar allocates the instance, seeds the argument slots, drives the step
function and frees it, all inside one `for` statement — the generator has no
lifetime of its own. A VALUE needs the instance to outlive the expression that
made it, which means an object with the instance pointer, the step function's
address, and a `__next__` that calls it. PXX cannot call through a stored proc
pointer with arguments (the desugar's own comment records this), so the step
call has to stay a direct call the compiler emits, or that restriction has to
go first.

The consumption side then wants the FPC structural enumerator protocol that
`parser.inc` already implements — `GetEnumerator` / `MoveNext` / `Current` —
which is where `for t in some_object` should land: `__iter__` -> `GetEnumerator`,
`__next__` -> `MoveNext` + `Current`, `StopIteration` -> False.

## Reach

Not measured against the corpora. Measure before ranking: the ladder's files
were unblocked by the CALL form, so this may buy less than it looks. That is
why `prio:` sits below the shim work rather than beside it.
