---
track: N
prio: 60
type: bug
blocked-by: []
summary: "`obj.m(**d)` is a parse error -- `expected expression` -- while the identical `f(**d)` on a plain function WORKS. A CONSTRUCTOR call `C(**d)` is refused the same way, so the subject is not the METHOD call but any call with a receiver or a class name in front of the parenthesis. Dict-unpacking into these is rejected, pure-Python classes included, so it is not a shim or binding issue but the call parser. CPython runs all of these, so it is an upward-compatibility break by Track N's own rule. IT IS NOW A CORPUS WALL: lekkerzeilen/world.py:447 `Furniture(**dict(zip(columns, row)))` is the first error in world and, through `from . import world`, in atlas -- two modules."
status: backlog
owner: unassigned
---

# `**` unpacking is rejected at a method call, but works at a function call

- **Type:** bug — **Track N** (Nil-Python frontend, the call parser).
- **Filed:** 2026-08-30 by frankB, found while sizing
  [[feature-lib-mimic-string-template]] — `logging.StringTemplateStyle` calls
  `self._tpl.substitute(**values)`, which is exactly this shape.
- Measured against **pin v395** (`aa78a7faf63a`), the Track B stable.

## Why this is a bug and not a divergence

Track N's rule is upward compatibility: *if code works on CPython, it must work
on NilPy.* Every program below runs under CPython 3.12 and prints the value in
the last column. Two of the four do not compile here.

## The boundary, measured

| call shape | pxx v395 | CPython |
| --- | --- | --- |
| `f(**d)` — plain **function**, `def f(**kw)` | **ok**, prints `2` | `2` |
| `string.capwords(**{'s': ...})` — Pascal shim **function** | **compiles** | — |
| `c.m(**d)` — **method** on a pure-Python class, `def m(self, **kw)` | **`error: expected expression`** | `2` |
| `c.m(**d)` — **method** with named params, `def m(self, a=0, b=0)` | **`error: expected expression`** | `3` |

So the failing axis is **method call**, not "shim", not "keyword binding", and
not `**kwargs` in the callee's signature — the fourth row's callee has ordinary
named parameters and still fails. A plain function accepts the very same
argument expression.

`expected expression` at the `**` token says the parser never gets as far as
binding: the argument list of a method call does not admit the `**` form at all.

## Repro — 6 lines, no imports

```python
class C:
    def m(self, a=0, b=0):
        return a + b
c = C()
print(c.m(**{'a': 1, 'b': 2}))
```

```
pascal26:5: error: expected expression
  near: print  c  m  >>>
```

CPython prints `3`. The plain-function counterpart compiles and runs correctly
here, which is the control:

```python
def f(a=0, b=0):
    return a + b
print(f(**{'a': 1, 'b': 2}))
```

## Why prio 45 rather than higher

Nothing in the tree is blocked *today*: `feature-lib-mimic-string-template` is
being built to the mapping form (`substitute(mapping)`), which is valid CPython
and needs no unpacking. But `**` at a method call is ordinary Python that
appears throughout real code, and the diagnostic points at the argument rather
than saying the form is unsupported, so the next person to hit it will read it
as a mistake in their own source.

## The single-star form IS different — measured, not left as homework

An earlier draft of this ticket guessed that `*args` might fail the same way and
that the two would be one fix. **That guess was wrong**, and the measurement is
the useful part of this ticket, so it replaces the guess rather than sitting
beside it.

| call shape | pxx v395 | CPython |
| --- | --- | --- |
| `c.m(*[1,2])`, method **without** defaults (`def m(self, a, b)`) | **ok**, prints `3` | `3` |
| `c.m(*[1,2])`, method **with** defaults (`def m(self, a=0, b=0)`) | explicit refusal (below) | `3` |
| `c.m(**{...})`, method **without** defaults | **`error: expected expression`** | `3` |
| `c.m(**{...})`, method **with** defaults | **`error: expected expression`** | `3` |

The `*` refusal is a real diagnostic that names its own reason:

```
error: Nil Python: *unpacking into C.m is not supported — it has parameters
with defaults, whose values a compile-time expansion cannot preserve
```

So these are **two gaps with different shapes**, and fixing one does not fix the
other:

- `*` at a method call is **implemented**, with a deliberate and honestly stated
  limit: it is a compile-time expansion, so it cannot reconstruct defaults. That
  is a design boundary, and widening it means runtime argument binding.
- `**` at a method call is **not parsed at all** — `expected expression` at the
  `**` token, identical with and without defaults, so the callee's signature is
  never consulted. That is a missing production in the argument-list grammar,
  not a limit anyone chose.

**The `**` half is the one to fix first**: it is a parser gap rather than a
design boundary, its diagnostic misleads (it points at the argument, not at the
unsupported form), and the `*` refusal shows the codebase already has a place to
say "this form is not supported" properly when it must.

# The mechanism, traced 2026-09-10 (frankB, compiler `df4aebdbbf51`)

Recorded while fixing the single-star sibling
([[bug-n-star-unpacking-is-rejected-at-a-method-call]], now closed by frankZ's
`f98fd53d7`), because the trace answers this ticket's open question and would
otherwise have to be done twice.

**`f(**d)` at a plain function call works because it reaches a DIFFERENT
implementation from the one a method call reaches**, not because the method
parser lost a production it once had.

| door | who parses the argument list | dict half |
| --- | --- | --- |
| plain function | `PyStarMixedForwardCall` → `PyStarForwardCall` — hoists a `TPyList` and a `TPyDict`, then dispatches on `len(args)` at RUN TIME | yes, since it was written |
| method / constructor | `PyStarExpandCallArgs` — a COMPILE-TIME expansion, one `pystar_arg(l, i)` per declared slot | **none at all** |

So `expected expression` is honest: at a method call nothing in the grammar
admits `**`, because the machinery behind that door has no concept of a keyword
dict to hand it to.

**The blocker for routing method calls to the working implementation is one
missing parameter.** `PyStarForwardCall(procIdx, listNode, dictNode)` fills the
callee's slots from **0**. A method's slot 0 is `Self`. There is no `firstSlot`
and no receiver node in the signature, so handing it a method today would bind
the receiver's slot out of the argument list. The single-star expander already
takes `firstSlot` for exactly this reason — that is the shape the forwarder
needs, plus a hoisted receiver assigned into slot 0.

**This ticket's own recommendation was written before either mechanism was
traced and reads the wrong way round on the measurement.** It says *"the `**`
half is the one to fix first"* on the grounds that `*` was a design boundary
and `**` merely a parser gap. The `*` half turned out not to be a design
boundary at all — it needed no runtime binding, only the default-value node the
compiler already builds for every short ordinary call, plus the run-time length
probe next door — and it landed as a contained change to one function. `**` is the larger job of the two: it needs a
receiver-aware forwarder. Left standing rather than edited, because the
prediction being wrong is the useful part.


---

## 2026-09-10, frankB — it is a CORPUS wall now, and the population is wider than "method"

Measured at compiler `8ea6cf9845db`, after `mimic_sqlite3` cleared the wall in
front of it:

```
lekkerzeilen/world :: pascal26:447: error: expected expression
lekkerzeilen/atlas :: pascal26:447: (the same, through `from . import world`)
```

world.py:447 is `into.append(Furniture(**dict(zip(columns, row))))` — a
**constructor** call, not a method call. Reduced:

```python
class Furniture:
    def __init__(self, a, b): ...
def f(a, b): ...
d = {"a": 1, "b": 2}
print(f(**d))            # compiles
print(Furniture(**d).a)  # pascal26:11: error: expected expression
print(c.m(**d))          # pascal26:7:  error: expected expression
```

So the title understates it: a plain function takes `**`, and **anything with a
receiver or a class name in front of the parenthesis does not** — method and
constructor are two doors of one gap, and a fix aimed at the method call alone
would leave world.py exactly where it is. Re-ranked 45 -> 60 on the two modules
it now blocks; the ranker will carry that up the lekkerzeilen umbrella. Not
taken — recorded so whoever takes it fixes both spellings and has a corpus line
to verify against.
