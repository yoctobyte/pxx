---
track: N
prio: 70
type: bug
summary: "Every non-constant parameter default silently becomes None on the ordinary call path — `def f(b=[])` gives b=None, and so does `def f(b=w)` for any name w. Only the closure-VALUE path evaluates defaults at def time."
---

# Non-constant parameter defaults silently become `None`

- **Type:** bug (NilPy) — **Track N**
- **Found:** 2026-08-02, sweeping function semantics against the CPython oracle.
- **SILENT.** The parameter is simply None; nothing is reported at compile time
  or at run time until something downstream touches it.

## Measured

```python
def acc(v, bucket=[]):
    bucket.append(v)
    return bucket
print(acc(1))        # CPython [1]      pxx  AttributeError: 'NoneType' has no attribute 'append'
```

```python
def f(b=[]):   return b      # CPython []     pxx None
def f(b={}):   return b      # CPython {}     pxx None
def f(b=()):   return b      # CPython ()     pxx None
w = 7
def f(b=w):    return b      # CPython 7      pxx None
w = [1, 2]
def f(b=w):    return b      # CPython [1, 2] pxx None
```

CONSTANT defaults are fine and unaffected: `b=10`, `b="z"`, `b=True`, `b=None`,
`b=2.0`, `b=-1` all work.

So the rule is: **anything that is not a literal scalar token becomes None.**

## Cause

`PyParamDefaultAt` (pyparser.inc) recognises a fixed set of literal tokens
(`tkInteger`, `tkString`, `tkFloat`, `tkTrue`, `tkFalse`, `tkNil`, and a negated
number). Anything else falls into the final `begin ... end` block, which SKIPS
the expression's token span and leaves the parameter as a None-valued optional.
Its own comment says so, and justifies it for uforth's native-word bodies, which
only ever run through the exec/native stub.

That justification no longer covers what the frontend is used for.

## This is NOT covered by the closure-default fix

`feature-nilpy-closure-default-and-remaining` (in `done/`) records
"Closure-captured parameter defaults: FIXED", re-measured against CPython. That
is true but **narrower than it reads**: the def-time re-parse that implements it
lives in `PyNestedDefClosureValue` (pyparser.inc ~4898), so it only runs when a
nested def is materialised as a closure VALUE. A def that is simply *called*
never goes through it:

```python
def outer():
    w = 7
    def inner(b=w):
        return b
    return inner()      # called directly -> None, not 7
print(outer())
```

So the ordinary path was never fixed, and the "FIXED" note should be read as
"fixed for the closure-value path".

## Shape of the real fix

Python evaluates a default **once, at def time** — which is also what makes the
shared-mutable-default gotcha (`acc(1)` -> `[1]`, `acc(2)` -> `[1, 2]`)
observable. So a fresh-per-call empty container would be the WRONG fix: it gets
the common case right and diverges on the accumulator idiom, trading one silent
divergence for a subtler one.

The honest shape, and it mirrors the `$clsattr` machinery that already exists for
class attributes:

1. for a non-constant default, allocate a hidden global `$pdef.<proc>.<param>`
2. hoist `<global> := <expr>` at the DEF statement, so it is evaluated once, in
   the scope where the def stands
3. record the symbol in a new PARALLEL array beside `ProcParamDefaultVal` —
   **not** a new field on the proc record
   ([[project_tsymbol_field_landmine]] is the same hazard one level up)
4. the omitted-argument fill emits an ident on that global instead of the ordinal

Step 4 is the awkward part: the fill is done at **four** sites in `parser.inc`
(~2594, ~2602, ~2628, ~12381), all on the shared call path, so this is a Track A
change under the self-host gate and wants doing in one pass rather than
incrementally.

## Interim option, if the full fix is not being taken

Make a non-constant default a LOUD error rather than silently None. Strictly
better than today — but check the uforth corpus first, because the current
silence is what lets its native-word bodies compile at all, and that is the
reason the behaviour exists.

## Gate

A `.npy` diffed against CPython: empty `[]`/`{}`/`()` defaults; a name default
bound to both a scalar and a container; the accumulator idiom across three calls
(pinning the SHARED semantics, not fresh-per-call); a default referring to an
enclosing local, called both directly and as a returned closure; and every
constant-default form as a regression control.
