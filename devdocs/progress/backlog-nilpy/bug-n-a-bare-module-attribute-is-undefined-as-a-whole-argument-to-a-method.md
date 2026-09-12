---
track: N
prio: 75
type: bug
blocked-by: []
summary: "`o.m(math.pi)` gives `error: undefined variable (math)` — a module-qualified attribute as a WHOLE argument to a method call on a NAME receiver. Six lines, single file, stdlib math. MEASURED MECHANISM (2026-09-12, second pass): the argument is PARSED TWICE. PyParseFactorCore resolves it CORRECTLY first (ConsumeUnitQualifier answers unit 651, `pi` resolves), then the position REWINDS and the same tokens are re-parsed through PyParseLValueAST, which has no unit-qualifier door and halts. A constructed receiver (`A().m(..)`) parses once and compiles. So the defect is a REDUNDANT SECOND PARSE, not a missing lookup — the first pass of this ticket concluded the opposite and is corrected in place, because that framing sends the reader to add a duplicate door at the error site. Do NOT make the site recoverable either: it would poison the name into a stand-in and emit a wrong value instead of refusing. Next step is to identify the REWINDER (eleven ParseLValueAST call sites, all in pasparser_lval.inc; not ParseIntrinsicDestLValue, checked). PRE-EXISTING — the pinned compiler fails identically. THIS IS THE WALL ON THE lekkerzeilen CLOSURE (goal 4), app.py:2959; 29 `ui.` sites in app.py."
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

## CORRECTED 2026-09-12, second pass: THE DOOR IS ASKED AND IT SUCCEEDS

**Read this section before the one below it, which it corrects.** The first pass
concluded *"the door is not missing, it is not consulted"* and that framing is
wrong in the direction that matters: it sends the reader to add a
`FindUnitOrAlias` call at the error site, which is not the fix.

Probed at BOTH the factor call site (`pyparser.inc`, `qUnit :=
ConsumeUnitQualifier(name)` inside `PyParseFactorCore`) and at
`PyParseLValueAST`'s entry, in the failing and the working case, with the
binary afterwards verified byte-identical to `82215bad2750`:

```
FAILING  o.m(math.pi):
  PROBEFC      factor name=pi  qUnit=651  TokPos=38     <- SUCCEEDS
  PROBELV-ENTRY      name=math idx=-1     TokPos=37     <- rewound, re-parsed
  pascal26:6: error: undefined variable (math)

WORKING  A().m(math.pi):
  PROBEFC      factor name=pi  qUnit=651  TokPos=38     <- and nothing else
```

**The argument is parsed TWICE on the name-receiver path.** The first parse is
`PyParseFactorCore`, it consumes `math` as unit 651 through
`ConsumeUnitQualifier`, resolves `pi` in it, and is CORRECT. Then the position
rewinds — 38 back to 37, `identTok` 35, i.e. the same `math` token — and the
same argument is re-parsed through `PyParseLValueAST`, which has no unit
qualifier door and halts. The constructed-receiver path parses it **once** and
compiles.

So the defect is the REDUNDANT SECOND PARSE, not a missing lookup. This is the
`ad7c03b03` shape named in CLAUDE.md under "A SPECULATIVE PARSE AND THE
COMMITTED ONE CAN DISAGREE", with the polarity reversed: there the probe's
reading was right and the committed one built something else; here the first
reading is right and the second one refuses.

### It is not a suppressible probe — checked

There is no speculative-mode flag to consult: the machinery is `ErrorRecover` +
`ErrCount` + `PoisonSym` (`defs.inc:4957`, `defs.inc:318`), and the NilPy site
calls `Error` (halt) where its Pascal twin `ReportUndefinedName`
(`pasparser_lval.inc:223`) calls `ErrorRecover`. **So do not "fix" this by
making the site recoverable** — that would poison `math` into a stand-in symbol
and emit wrong code instead of refusing, converting a loud compile error into a
plausible wrong value. That is strictly worse.

### The two candidate fixes, and why neither was taken

1. **Remove the second parse** — the root-cause fix. The rewinder was NOT
   located: `ParseLValueAST` has eleven call sites, all in
   `pasparser_lval.inc`, and the one on this path is not
   `ParseIntrinsicDestLValue` (checked). Whether the re-parse is load-bearing
   for overload selection is unknown.
2. **Give `PyParseLValueAST` the qualifier door.** Small and probably works, but
   it is a second copy of a door that already exists and already answered
   correctly thirty tokens earlier — `devdocs/dev/normalise-dont-special-case.md`
   is about exactly this, and the sibling bugs this argument path has already
   produced (a bare genexpr, a bare Delphi routine name) are what that file is
   citing.

**Identify the rewinder first.** A marker threaded through the eleven
`ParseLValueAST` call sites, or a probe on whatever saves and restores `TokPos`
on the name-receiver method path, answers it in one build.

## SUPERSEDED first pass: "the door that is never asked"

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
   missing, it is **not consulted here**. *(CORRECTED above: it IS consulted
   earlier, by the factor parse, which succeeds. This site is a redundant second
   reading of the same tokens. The observation stands; the conclusion drawn from
   it did not.)*
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
produced the two sibling bugs named above. CORRECTED on the second pass: the door is found, it is `ConsumeUnitQualifier` in `PyParseFactorCore`, and it already runs and succeeds — find the REWINDER instead.

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
