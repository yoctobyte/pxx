---
track: U
prio: 65
type: decide
summary: "How should `inst.attr` read a CLASS attribute? Full Python fall-through with per-instance overrides (correct, invasive), or a whole-program static specialisation using the PyDynAttrEverAssigned-style scan already in the frontend (cheaper, correct for programs that never override per instance)? Blocks bug-nilpy-class-attribute-unreachable-through-the-class-name."
---

# `inst.attr` on a class attribute — which read model?

- **Type:** decision (Track U) — filed 2026-08-02
- **Blocks:** [[bug-nilpy-class-attribute-unreachable-through-the-class-name]]
  (prio 65), which has been attempted and reverted twice and whose own write-up
  concludes the read model has to change *first*.

## The fork

Today a NilPy class attribute is **copied into a real instance field at
construction** (`PyClassAttrInitSeq` for a class with a ctor,
`PyParseNewInstance`'s hoisted-temp form without one). Reads and writes through
an instance are ordinary field access. That is indistinguishable from Python for
every program that never writes through the CLASS NAME — which is exactly why
`ClassName.attr` is a compile error today, and why enabling it would turn a loud
refusal into a silent wrong value:

```python
class S:
    v = 5
a1 = S(); a2 = S()
S.v = 10
print(a1.v, a2.v, S.v)    # CPython 10 10 10    copy model 5 5 10
```

So the read model has to change before `C.attr` can be enabled at all. Two
credible models, and they are not close in cost.

## Option A — full Python semantics (what the blocked ticket recommends)

Class attributes live only in the class (the hidden `$clsattr.<Class>.<name>`
global). Construction copies nothing. `inst.attr` reads the global unless the
instance has an override; `inst.attr = x` creates one, reusing the existing
`pydynattr` per-instance machinery.

- **Correct for every program**, including ones that override per instance and
  rebind through the class in the same run.
- Invasive: it changes how *every* NilPy class attribute is read and written,
  and adds a branch (or a dict probe) to a hot path that is a plain field load
  today.
- The per-instance override needs somewhere to live. `pydynattr` exists, but
  routing ordinary declared attributes through it is a much bigger commitment
  than the dynamic-attribute escape hatch it was built for.

## Option B — whole-program static specialisation

For each class attribute `nm` of class `C`, scan the module for an INSTANCE
write (`<expr>.nm = ...` where the receiver is not `C` itself, plus any
`setattr`). If there is none, no instance can ever override it, so:

- do not copy it into the instance at construction,
- lower `inst.nm` / `self.nm` to a read of the class global,
- lower `C.nm = x` to a write of that global.

That is **exactly** Python's observable behaviour for such a program, with no
runtime cost — a global load instead of a field load — and no override storage.
Attributes that DO get an instance write anywhere keep today's copy model
unchanged, so nothing regresses; `C.nm` on those stays refused (or is enabled
separately once A exists).

The frontend already does this kind of whole-module token scan and treats it as
the normal tool: `PyDynAttrEverAssigned` (`pyparser.inc:7117`) is literally
"does the module ever write `<expr>.nm = ...`", and `PyMethodUsedAsValue` beside
it keys the same way. So B is in-idiom, not a new mechanism.

**Known sharp edges of B**, stated honestly:

- It is name-keyed, not receiver-typed, like its two neighbours. An unrelated
  class writing `other.count = 1` would demote `C.count` to the copy model —
  conservative (falls back to today's behaviour), never wrong.
- Distinguishing `C.nm = ...` from `inst.nm = ...` at token level needs the
  receiver identifier compared against the class name — and NilPy identifiers
  were case-insensitive until recently, which is precisely how the blocked
  ticket's first revert got misdiagnosed. Worth a test.
- `exec`/`setattr`-style dynamism forces the fallback, correctly.

## Option C — leave it refused

`ClassName.attr` stays a compile error. The counter/registry idiom
(`C.count += 1` in `__init__`) — the main reason to write a class attribute —
stays unavailable. This is the status quo and the cost is a permanent, visible
hole in a very ordinary corner of Python.

## Recommendation

**B first, A later if a corpus program needs it.** B is a few hundred lines in
one file, reuses an established pattern, is conservative by construction (any
uncertainty falls back to today), and unblocks the whole
`ClassName.attr` ticket — including its parts 1 and 2, which the blocked ticket
already measured as *working* once the read model is sound. A is the honest
long-term model but it rewrites the instance-attribute path to buy behaviour no
measured program has needed yet.

If the answer is A, say so and the blocked ticket becomes a much larger piece of
work that should be scoped on its own. If it is B, the blocked ticket can be
picked up directly.

## Note for whoever decides

The blocked ticket's parts 1 and 2 have both been implemented and measured
byte-identical to CPython in isolation — the only thing that sent them back was
the `S.v = 10` case above. So this decision is the entire remaining blocker, not
one of several.
