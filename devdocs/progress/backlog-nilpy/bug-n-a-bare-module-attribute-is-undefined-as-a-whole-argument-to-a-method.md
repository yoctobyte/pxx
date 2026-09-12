---
track: N
prio: 75
type: bug
blocked-by: []
summary: "`o.m(math.pi)` gives `error: undefined variable (math)` — a module-qualified attribute as a WHOLE argument to a method call on a NAME receiver. Six lines, single file, stdlib math. THE DISCRIMINATOR IS THE RECEIVER FORM: a name receiver (`self.m(..)`, `o.m(..)`) fails, a CONSTRUCTED one (`A().m(..)`) works; the enclosing scope, keyword-vs-positional, and the argument's position are all irrelevant, and wrapping it in any expression (`0 + math.pi`) compiles. Hits every module qualifier, `import math` included, not just relative imports. PRE-EXISTING — the pinned compiler fails identically, so it is not from the 2026-09-12 star/arity/slice work that touched these sites. THIS IS THE WALL ON THE lekkerzeilen CLOSURE (goal 4), app.py:2959 (`self._write(.., leading=ui.ROW)`), reached after the extended-slice fix moved the closure 599 lines; 29 `ui.` sites in app.py."
---

# A bare `mod.ATTR` as a whole argument to a method is undefined

Found 2026-09-12 while walking the lekkerzeilen closure. Six lines:

```python
import math

class A:
    def m(self, a):
        print(a)

o = A()
o.m(math.pi)          # pascal26:6: error: undefined variable (math)
```

## What the probes separate

Measured against `compiler/pascal26` at `82215bad2750` **and** against the
pinned binary, which answers identically:

| shape | result |
| --- | --- |
| `o.m(math.pi)` — name receiver | **error: undefined variable (math)** |
| `self.m(1, math.pi)` — inside a method | **error** |
| `self.m(1, b=math.pi)` — keyword | **error** |
| `A().m(1, b=math.pi)` — CONSTRUCTED receiver | ok |
| `o.m(0 + math.pi)` — inside an expression | ok |
| `f(1, b=math.pi)` — a plain function | ok |
| `print(math.pi)`, `x = math.pi` | ok |
| `from . import ui` then `o.m(ui.ROW)` | **error** (same cause) |

**The receiver form is the whole discriminator.** Two earlier readings of this
were wrong and both are worth recording, because each came from a probe set that
moved two variables at once:

1. *"It is a keyword-argument bug."* Refuted by the positional row.
2. *"It only happens inside a method body."* Refuted by the top-level name
   receiver. That matrix had used a CONSTRUCTED receiver in its top-level rows
   and a NAME receiver in its method rows, so the scope and the receiver moved
   together and the result was read as being about scope.

## MEASURED: the exact site, and the door that is never asked

Instrumented at the failure point (`pyparser.inc`, the `else` arm of
`PyParseLValueAST` that ends in `Error('undefined variable')`), probe removed
again and the rebuilt binary confirmed byte-identical to `82215bad2750`:

```
PROBELV fieldName=math qualRecv=[] unitOrAlias=651 nextTok= kind=81
pascal26:6: error: undefined variable (math)
```

Three facts, and together they are the whole diagnosis:

1. **`FindUnitOrAlias('math')` answers 651** — a valid unit index — at the very
   moment the site decides the name is undefined. The module door is not
   missing, it is **not consulted here**.
2. `qualRecv` is EMPTY, so the sibling arm that would report `no member X came
   of the qualifier Y` cannot fire: the parser is sitting on `math` as a bare
   name, with the `.` still unconsumed (`kind=81`), and nothing has looked
   AHEAD to see that it is a qualifier.
3. In the working (constructed-receiver) case this site **is never reached at
   all**, so the two paths diverge before it.

### Three hypotheses measured and ruled out

Each was plausible, each was wrong, and each cost a rebuild — recorded so the
next reader does not re-spend them:

- **The argument loop.** `ParseArgExpr`'s own comment says seven
  parameter-driven argument loops exist and only five funnel through it, which
  made a bypassed loop the obvious suspect (it is the documented cause of two
  earlier bugs of this exact shape: a bare genexpr and a bare Delphi routine
  name as a method argument). Probed: **both** cases reach `ParseArgExpr` with
  `tok=math`. Not it.
- **`PyStarUnpackMethodArgs`.** Probed at entry: **never fires** for either
  case, so the name-receiver method call does not go through it.
- **`PyExprMode`.** Probed at `ParseArgExpr`: **TRUE in both** cases, so both
  take the `PyParseBoolExpr` arm. Not it.

### The fix, and why it is not done here

The remedy is to ask the door that already answers — and to ROUTE to whatever
the working path uses, not to add a fourth ad-hoc `FindUnitOrAlias` test. The
pattern the type-inference side already uses is `FindUnitOrAlias(root)` then
`FindProcInUnit(member, unit)` (`pyparser.inc:5940`; `math.pi` is a
parameterless proc, `math.sqrt` a callable). What is NOT yet located is the door
that EMITS that read on the working path, and guessing at it would make this the
fourth special case for one concept — the shape
`devdocs/dev/normalise-dont-special-case.md` is about, and the shape that
produced the two sibling bugs named above. Find that door first.

## Where to look

A name receiver and a constructed receiver reach different argument parsers —
`PyStarUnpackMethodArgs` (~`pyparser.inc:17174`) versus
`PyParseClassMethodCall` (~`17502`). **Both call `ParseArgExpr`**, so the
difference is not the argument parser itself; it is something established before
the loop. `PyExprMode` is the obvious suspect and is NOT it — it is set True
across NilPy parsing and cleared only around Pascal RTL units
(`pasparser_proc.inc:7027`).

The diagnostic is raised from `PyParseLValueAST` (`pyparser.inc:43651`) with
`ErrorIdent` = the module name and the bare `undefined variable` text, which
means `PyQualifierBefore(prevTok)` found **no** qualifier: the parser is sitting
on `math` as a bare name with `.pi` still unconsumed, rather than treating it as
a qualifier. The sibling arm in that same `else` block — the one that reports
`no member X came of the qualifier Y` — is the shape a correctly-identified
qualifier takes, so comparing how the two receiver paths arrive at that site is
the fastest route in.

Note `PyUnitAliasRootName` (`pyparser.inc:12738`) and the ticket
`bug-n-a-module-alias-does-not-resolve-for-attribute-lookup` are the same family:
a module door that one path consults and another does not.

## Gate

A `.npy` with a module constant passed to a method six ways: name receiver
(positional, keyword, sole argument), constructed receiver, inside an
expression, and through a plain function. The last three are reach-checks that
already pass — if they fail the harness is not reaching the fixture. The PINNED
compiler must refuse the name-receiver rows, which is the positive control and
is MEASURED, not predicted.
