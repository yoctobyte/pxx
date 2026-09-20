---
slug: bug-n-a-variant-field-is-claimed-as-the-callee-of-an-open-world-call-with-no-runtime-class-test
type: bug
track: N
prio: 60
status: open
summary: "When no class declares .m() as a method, the resolver claims any class's variant FIELD named m as the callee and emits an unconditional hard cast to that class — so a call on a receiver of a different class runs through whatever that field holds; the open-world dispatcher that would answer correctly is only reached when no such field exists anywhere"
---

## The mechanism, and the condition that springs it

`recv.m(args)` on a receiver with no static class is resolved by scanning for a
class declaring `m` as a method. When that scan finds nothing, two fallback
passes look for a FIELD named `m` — first one with a recorded procedural
signature, then any VARIANT one — and hand the first hit to
`PyMakeVariantFieldCall`. With a single candidate that builds **one arm, no
runtime class test**: a hard cast of the receiver to the candidate class and a
call through the field at that offset.

The population is a dispatch table (`w.native(vm)`, the field holding a
function value), where the receiver really is an instance of that class. The
condition that springs the bug is the receiver being an instance of some OTHER
class — then the cast is wrong and the call goes out through whatever lives at
that offset. A plain data field named like somebody else's method is enough.

It fires only where the method scan found nothing, which today mostly means the
declaring class is in a module imported LATER than the caller's —
`feature-n-register-the-class-shells-of-the-import-closure-before-parsing-any-body`.
The two together are lekkerzeilen blocker 03.

## Measured 2026-09-20, CPython 3.14.4 giving (3.0, 0.5) in every row

Two modules: `traffic.Craft` has a field `wind` and calls `env.wind(1.0, 2.0)`
on an unannotated parameter; `environment.Environment` declares `def wind`.
`__main__` imports traffic first.

| variant | shape | pxx |
| --- | --- | --- |
| v1 | field is `(0.0, 0.0)` | TypeError: object is not callable |
| v8 | field is `None` — **variant from birth, no widening** | identical failure |
| v3 | field is `0.0` | identical failure |
| v7 | result to a LOCAL, field never re-assigned | warns, and is CORRECT |
| v2 | environment imported first | correct |
| v6 | traffic.py holds the import edge | correct |

**v8 is the row that matters for whoever fixes this.** The first diagnosis was
that the unresolvable assignment WIDENED the field to a variant and the widened
field then satisfied the fallback — a self-fulfilling loop — and the fix was to
be a sentinel marking a widened field. v8 refutes it: `self.wind = None` is
variant from the start, nothing widens, and it fails the same way.
`self.wind = None` is the ordinary way to write the field, so that fix would
have repaired the rarer spelling. Do not re-derive it.

**v7 is the row that names the repair.** When no such field exists anywhere, the
resolver warns and emits `PyMakeDynMethCall` — open-world dispatch on the
receiver's own RTTI — and that gets the right answer. So the correct emission is
the is-test the multi-candidate path already builds, with the open-world call as
the ELSE arm:

    pyvarobj(v) is Craft ? <call through Craft.wind> : <pydyn_meth2(v,'wind',…)>

Cost is one class compare on these calls only, and the dispatch-table population
takes the first arm exactly as it does today.

## Why it is not a one-liner

`PyMakeVariantFieldCall` and `PyMakeDynMethCall` each **parse the argument list
themselves**, from the same token position, so the two arms cannot both be built
from one token stream as they stand. The work is to split the parse from the
build in `PyMakeDynMethCall` (its args land in `argExpr[]`/`argKw[]`, the field
path's in an `AN_ARG` chain plus two hoisted keyword lists) and give the builder
an entry point that takes them already parsed. The keyword channels differ — a
`kwspec` string there against `kwNames`/`kwVals` lists here — which is the part
to design rather than translate.

Three sites spell the same "a variant field is a callable field" rule
(the static-receiver route, the dynamic-receiver fallback, and the candidate
scan inside `PyMakeVariantFieldCall`). Whatever the rule becomes, it should
become ONE predicate — the static-receiver route at least has a genuinely known
class and needs no guard, and that difference is worth stating in code rather
than rediscovering.

## What would retire this

The v8 shape compiling and printing `(3.0, 0.5)` with the two declarations in
their original modules and no import edge added, and the dispatch-table fixture
(`self.cb = None`, armed with a module-level def, called through a dynamic
receiver) still printing its value.

## The repro, inline, because the scratchpad it was measured in does not survive a reboot

Three files under one directory, compiled with `-Fu<that directory>`:

`traffic.py`

    class Craft:
        def __init__(self):
            self.wind = None          # v1 writes (0.0, 0.0); v3 writes 0.0

        def update(self, env):
            self.wind = env.wind(1.0, 2.0)
            return self.wind

        def peek(self, env):          # v7: the same call, result to a LOCAL
            w = env.wind(3.0, 4.0)
            return w

`environment.py`

    class Environment:
        def wind(self, x, z):
            return (x + z, 0.5)

`main.npy`

    import traffic                    # v2 swaps these two lines and is correct
    from environment import Environment

    c = traffic.Craft()
    print("update", c.update(Environment()))
    print("peek  ", c.peek(Environment()))

CPython 3.14.4 prints `update (3.0, 0.5)` / `peek   (7.0, 0.5)`. pxx dies on the
`update` line. v6 — which is the workaround handed to lekkerzeilen — adds
`from .environment import Environment` to the TOP OF traffic.py and changes
nothing else; the import edge alone is enough, with the parameter still
unannotated.

The must-not-break half, to be carried in the same fixture: a class with
`self.cb = None` armed with a module-level def and called through a dynamic
receiver (`def fire(t): return t.cb(21)`). That is the dispatch-table population
the field passes exist for, it works today, and it must still print its value.
