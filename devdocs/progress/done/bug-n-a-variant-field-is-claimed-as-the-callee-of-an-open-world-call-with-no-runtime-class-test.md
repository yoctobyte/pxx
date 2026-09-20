---
slug: bug-n-a-variant-field-is-claimed-as-the-callee-of-an-open-world-call-with-no-runtime-class-test
type: bug
track: N
prio: 60
status: done
owner: frankb-8e
resolved: 2026-09-20
summary: "RESOLVED 2026-09-20 — PyMakeVariantFieldCall now `is`-tests EVERY candidate and falls back to open-world pydyn_meth dispatch, which is exactly the emission this ticket prescribed. Both unchecked arms are gone: the `nc = 1` short-circuit that skipped the test entirely, and the last candidate as an unconditional else. THE READ PATH HAD ALREADY DELETED THESE TWO ARMS ON 2026-09-13 and the CALL path was not migrated with it — that fix's own rule was `the READ and the WRITE must agree about which names dispatch`, read and write were made to agree, and CALL is the third spelling. Closes lekkerzeilen blocker 03: the owner's UNMODIFIED checkout (c9f8e2d, no import edge, no diff) now builds rc=0 and runs `--shot --for 20` to completion with a rendered frame, where it died before frame 2. Speed still reads 0.0 kn — that is blocker 04, untouched, and it is exactly what the one-line 03 workaround alone was independently measured to produce, which is corroboration that this moved 03 and nothing adjacent. BOTH RETIREMENT CONDITIONS THIS TICKET STATED WERE MEASURED, not inherited: the v8 shape (`self.wind = None`, variant from birth) prints (3.0, 0.5) with the declarations in their original modules and no import edge added, and the dispatch table (`self.cb = None` armed with a module-level def, called through a dynamic receiver) still prints its value. Positive control measured against PINNED v413 f94c2a7e2396d2be — an independently built pre-fix compiler, not one made for the occasion — which dies on the first row. NOT COVERED, stated at the branch in code: a KEYWORD call through a variant field keeps the old hard cast, because the keywords are already hoisted into TPyList temps here while pydyn_meth wants a kwspec string, and PyDynMethL refuses a kwspec on its callable-attribute arm — routing them there would trade a wrong answer for a new refusal. SECOND RESIDUAL, ARITY: the fallback asks FindProc for a `pydyn_meth<n>` rung and today those stop at 4, so a call of FIVE or more arguments through a variant field also keeps the old unchecked cast. The list path (pydyn_methl) is NOT the repair — it needs hoisted appends and hoisting escapes a ternary branch here (bug-n-a-hoisted-argument-escapes-a-ternary-s-untaken-branch), and every arm built here IS a ternary, so it would trade a wrong receiver for wrong evaluation order on calls that are correct today. Both residuals are the `part to design rather than translate` this ticket named, both are stated at the branch in code, and both wait on the same thing: a branch-aware hoist."
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

## RESOLVED 2026-09-20 — frankb-8e

Fixed in `PyMakeVariantFieldCall` (`compiler/pyparser.inc`), compiler
`05e1d35cd993`, `converged after 1 round(s)`. The emission is the one this
ticket specified, unchanged:

    pyvarobj(v) is Craft ? <call through Craft.wind> : <pydyn_meth2(v,'wind',…)>

**"Why it is not a one-liner" was right about the obstacle and the split is
done.** `PyMakeDynMethCallFromArgs` takes an already-parsed `AN_ARG` chain and
builds the same `pydyn_meth<n>(recv, 'name', a0..)` call. It allocates FRESH
`AN_ARG` nodes over the shared value nodes — relinking the caller's chain would
splice this arm's prefix into the other arms, which is what makes "the arguments
are parsed once" true.

It asks `FindProc` for the rung instead of restating `MAX_DYN_RUNGS`, which is
declared ~3600 lines away. pyeval's own comment records that cap being *"true at
95e7eb26e and stopped being true later the SAME DAY"*, so a restated copy is a
stale value waiting to happen; an absent rung now simply returns -1 and leaves
the old shape.

**THE KEYWORD CHANNEL IS NOT TRANSLATED, AND THAT IS THIS TICKET'S OWN "PART TO
DESIGN RATHER THAN TRANSLATE" SURVIVING.** The keywords here are already hoisted
into `TPyList` temps whose contents are known only at run time; `pydyn_meth`
wants a `'|'`-separated `kwspec` string. `PyDynMethL` refuses a kwspec on its
callable-attribute arm outright (*"takes positional arguments only"*), so routing
them there trades a wrong answer for a new refusal. A keyword call through a
variant field on a receiver that is none of the candidates therefore still hard
casts. Narrowed, stated at the branch in code, and the residual.

**AND A SECOND RESIDUAL I NEARLY LEFT UNDOCUMENTED, WHICH IS THE WORSE HALF
BECAUSE IT LOOKS LIKE A NO-OP.** The fallback asks `FindProc` for a
`pydyn_meth<n>` rung and returns -1 when there is none, and the caller then
keeps its previous shape. That reads as tidy defensive coding; what it MEANS is
that an arity past the last rung — today `pydyn_meth0..4`, so **five or more
arguments** — still hard-casts. I wrote the keyword residual into the summary
and missed this one until re-reading my own diff.

`pydyn_methl` serves those arities and is **not** the repair. It takes the
arguments as a `TPyList`, which means hoisted appends, and
`PyMakeDynMethCall`'s own comment records that hoisting in this frontend
**escapes a ternary branch**
(`bug-n-a-hoisted-argument-escapes-a-ternary-s-untaken-branch`). Every arm built
here IS a ternary branch, so routing the fallback through the list would
evaluate arguments on arms the `is` tests do not take — trading a wrong
receiver for wrong evaluation order on calls that are correct today. Both
residuals wait on the same thing, which is the condition `PyMakeDynMethCall`
already names for merging its own two paths: a branch-aware hoist.

## Both retirement conditions, MEASURED

This ticket set its own bar and both rows were measured rather than inherited.

| condition | result |
| --- | --- |
| v8 (`self.wind = None`), original modules, **no import edge added** | `(3.0, 0.5)` |
| dispatch table: `self.cb = None` armed with a module-level def, called through a dynamic receiver | `42` |

The second is the must-not-break population: the receiver really IS the
candidate class, the `is` test matches, and the **direct** arm runs. A fix that
routed everything to the dynamic dispatcher would pass every other row and lose
that one, which is why it shares a fixture with them.

**Positive control: PINNED v413 `f94c2a7e2396d2be`** — a pre-fix compiler built
by someone else for another purpose, rather than one produced for this check —
dies on the fixture's first row with `TypeError: object is not callable — the
name is None`.

## The control that names the mechanism, and it is better than v6

v2 in the table above is the sharp one and deserves promoting over v6. It
**changes no code at all** — it swaps the two import lines in `__main__.py`.
v6, the workaround handed to lekkerzeilen, ADDS an import, and an added import
cannot separate *"the declaring class is registered"* from *"the module is
imported"*. The swap can, and it puts the cause on registration order rather
than on anything about `traffic.py`.

## THE WARNING IS NOT THIS DEFECT'S SIGNATURE — THE CORRELATION IS INVERTED

Measured at `3c6e31f94a62d295`: the repro emits **ZERO** warnings and fails; the
`control_field_renamed` control emits **SIX** and is correct. `no class declares
a method or callable field .X()` fires when the scan finds **nothing** and defers
to run time — the safe arm. This defect is the scan finding something **wrong**
and binding to it silently.

The fixture carries a `.gust()` row for exactly this reason: it is the only row
that warns, and it is a row that always passed.

## Test

`test/test_nilpy_a_call_through_a_variant_receiver_dispatches_on_the_real_class.npy`
with package `test/nilpy_callorder/`, wired into `test-nilpy`. The oracle is
CPython on the same file, so no expected output is restated here and no row is a
default, a width or an empty value. It is written in the FAILING import order;
in the passing order it would have certified the defect.

## What this does NOT close

- **Blocker 04** — untouched, still open, still the reason the demo reads 0.0 kn.
- **Blocker 05** — a reduction of the read-path twin was built and **PASSED**,
  matching CPython, so the hypothesis that it is this defect's read spelling is
  refuted. That is the third reduction that fails to capture 05; its own README
  predicts this. Nobody has a reproduction smaller than the demo.
- **Blocker 06** — the same family and the OPPOSITE direction: 03 is a decision
  taken with too FEW classes registered, 06 is a wrong bind appearing when one
  MORE is. That is load-bearing, because it is evidence against the repair
  anyone would reach for first — see
  `feature-n-register-the-class-shells-of-the-import-closure-before-parsing-any-body`.

## The cost, measured on the largest NilPy program we have

"`is`-test every candidate and add a fallback arm" invites the question, so here
is the number rather than a reassurance. lekkerzeilen, same source, same flags,
the two compilers either side of this change:

| | code | procs |
| --- | --- | --- |
| before | 12,021,473 B | 11,589 |
| after | 12,042,528 B | 11,589 |

**+21,055 bytes, +0.175%**, and the proc count is unchanged — the arms are
inline ternaries, not new routines. Run time is one tag compare plus one class
compare per candidate, and only on calls that reach this path at all.

Note what does NOT reach it: a METHOD call on a variant receiver goes through
`PyParseVariantMethod`'s own dispatch, not here, so the demo's hottest
dynamically-dispatched site (`canopy.contains()`, ~1112 calls per frame) is
untouched by this change.
