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

## 2026-08-01 — FIXED. TWO holes, not one; the guard was dead for every block

Both measured, both in `PyAllocModuleGlobals`/`PyCollectModuleLocalsAST`, and
the first one is a one-token ordering bug that had disabled a guard entirely.

### Hole 1 — `blockIsDef` was never True, for ANY block

`PyCollectModuleLocalsAST`'s harvest is guarded by `not blockIsDef[depth]`,
whose whole job is to keep names bound inside a `def`/`class` out of the module
widening table. It never fired, because the flag clobbers itself:

```pascal
if (i = PyScanLo) or (Tokens[i-1].Kind in [tkNewline, tkIndent, tkDedent, tkSemicolon]) then
  pendingDefClass := (Tokens[i].Kind = tkFunction) or (Tokens[i].Kind = tkClass);
if Tokens[i].Kind = tkIndent then
  ... blockIsDef[depth] := pendingDefClass;
```

A body's `tkIndent` is itself preceded by `tkNewline`, so the INDENT token
passes the statement-boundary test and resets `pendingDefClass` to False (an
INDENT is not `tkFunction`) — **in the same iteration** the indent branch then
reads it. Measured directly with a probe on the harvest site:
`blockIsDef=0 depth=1` inside a def body, in every arrangement tried
(def first, def after a statement, def after a comment).

Fixed by excluding the layout tokens from recomputing the flag, and by making a
nested block INHERIT its enclosing block's def-ness (`if`/`for` inside a def is
still def scope — that was a second, quieter gap).

### Hole 2 — a def-LOCAL assignment counted as a READ of the global

Fixing hole 1 corrected the module table (`<module> zz tk=6`) but the repro
still failed, because `PyAllocModuleGlobals` separately pre-creates a global as
a bare variant when a def above it "reads" the name — and its scan counts any
matching identifier, including the def's own local assignment. Same shape as the
parameter case fixed earlier today, second half as predicted there.

New `PyDefBindsNameLocally` answers "does this def bind nm in its body", honouring
Python's actual rule — an assignment anywhere makes the name local for the WHOLE
function — and honouring `global nm`, which takes the shadowing back so the body
really is writing the module global and its uses DO count again. Covers plain
`nm =` and `for nm in`; `with ... as nm` and comprehension targets stay
conservative (treated as not binding, i.e. unchanged behaviour) and are the
remaining gap.

Not a perf regression: def bodies do not overlap, so summing these scans over
one caller pass is still one pass over the tokens — this does not reintroduce
the `PyFindBodyEnd`-per-construct blowup that once cost uforth 107 seconds.

### Verified

`test/test_nilpy_def_local_shadows_module_global.npy`, wired into
`make test-nilpy`, byte-identical to CPython. Covers def-local assignment,
for-target, nested-if-inside-def, `global` writing through, a module-level
control-flow block still being harvested (the harvest's original purpose), and —
the one most at risk from this fix — a def that only READS a global assigned
further down, which is the shape `PyAllocModuleGlobals` exists for.

Confirmed RED on the pre-fix binary: `hello / None / TypeError: expected a
number, got str`. Native: build + byte-identical self-host fixedpoint,
`testmgr --tier quick` 12/12 GREEN.

## Log
- 2026-08-01 — resolved, commit PENDING.
