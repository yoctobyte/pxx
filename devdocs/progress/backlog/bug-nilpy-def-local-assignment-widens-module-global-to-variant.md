---
summary: "NilPy: a name assigned as a LOCAL inside a def widens the same-named module global to tyVariant, killing its class identity and every compile-time dunder dispatch"
type: bug
track: N
prio: 70
---

# A def-local assignment widens the same-named module global to a variant

- **Type:** bug (NilPy type inference / scoping, silent) — **Track N**
- **Opened:** 2026-08-01. Split out of
  [[bug-nilpy-global-shadowed-by-method-param-name-loses-class-type]], whose
  own notes predicted these were two paths into one symptom. They are — the
  param path is fixed, this one is not, and it lives in a different pass.

## Repro

```python
def f():
    zz = "hello"          # a LOCAL of f; Python binds it in f's scope only
    return zz

class V:
    def __init__(self, n):
        self.n = n
    def __add__(self, q):
        return "ADD" + str(q.n)

zz = V(1)                 # module global, unrelated to f's local
p = V(2)
print(zz + p)             # CPython ADD2    pxx TypeError: expected a number, got object
```

Rename either side and it works. The def must appear ABOVE the module-level
assignment.

## Measured

`PXXDBG=n.locals` shows the module constraint table is genuinely WRONG here —
unlike the param case, where it was correct and irrelevant:

```
PXXDBG n.locals <module> zz tk=22 rec=0        <- tyVariant, should be tyClass
```

So the def's local `zz: tyString` is being folded into the MODULE widening
table, which then types the global as a variant (`tyString` ∪ `tyClass` →
`tyVariant`), and a variant operand never reaches compile-time dunder dispatch.

That is a different mechanism from the fixed sibling bug, which was
`PyAllocModuleGlobals` pre-creating the symbol and never consulted the table at
all. Do not assume the same fix shape applies.

## Where to look (measure, do not guess)

`PyCollectModuleLocalsAST` already carries a lexical `blockIsDef[depth]` guard
whose entire job is to keep names bound inside a `def`/`class` body out of the
module table, and the harvest branch does test it. So either the poisoning
reaches `PyLocals` by a path that does not go through that branch (the depth-0
bare-assignment branch trial-parses via `PyParseStatement`, and
`PyNoteLocalType` at the assignment site writes the SAME `PyLocals` array used
for both module and per-proc collection), or `blockIsDef` is not set for this
shape. Print it; the sibling ticket burned three plausible stories that all
died to measurement.

**Note the `global` keyword.** Unlike a parameter, a local assignment CAN be
overridden by `global zz` in the body, in which case the write really is to the
module global and folding its type in is correct. Any fix must honour that, or
it will break the opposite case.

## Impact

Silent. The global keeps working for attribute access and `isinstance`, so the
object is fine — only operator dispatch fails, with a `TypeError` far from the
cause. `i`, `n`, `s`, `key`, `value`, `item`, `result`, `data` are all ordinary
def-local names AND ordinary module-global names, so collisions are easy to hit
by accident in any file with module-level state.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython covering: def-local vs module global, a `global`-declared write (which
must still widen), attribute access and operator dispatch on the same variable,
and a non-colliding control.
