---
track: N
prio: 75
type: bug
blocked-by: []
summary: "FIXED 2026-09-12 — `o.m(math.pi)` gave `error: undefined variable (math)`, naming the MODULE and not the member. ROOT CAUSE: `ByRefArgStartsExpression` (`compiler/pasparser_call.inc`), the predicate that decides whether a by-ref or open-array argument can be a bare variable lvalue. Its lvalue-CHAIN skip walks `ident . ident` and then judges by the FOLLOWING token, so `math.pi` and `obj.field` are indistinguishable to it — both end at `)`, both were judged bare-lvalue, and the module one then reached ParseLValueAST with FindSym = -1 and halted. THIS IS THE THIRD INSTANCE OF ONE FAMILY IN ONE PREDICATE: the two clauses already sitting there record the same symptom for a bare parameterless FUNCTION and a bare parameterless METHOD, also gated on `FindSym < 0`, also method-only, also fine through a free function. FIX is a fourth clause beside them: root resolves no symbol, a `.ident` follows, and `FindUnitOrAlias` knows the root -> answer True, so the argument takes the ParseArgExpr path that PyParseFactorCore was ALREADY resolving correctly. Gated as narrowly as its neighbours. Fixture `test/test_nilpy_module_attr_method_arg.npy`, 11 rows, CPython-identical, wired into `test-nilpy`; positive control measured — the pinned binary refuses row MODQ. ADVANCED THE lekkerzeilen CLOSURE 2959 -> 3215."
status: done
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

## Resolved 2026-09-12 — the rewinder was a PREDICATE, not a missing door

`ByRefArgStartsExpression` in `compiler/pasparser_call.inc` decides whether an
argument bound to a **by-ref or open-array** parameter may be parsed as a bare
variable lvalue. Under `if PyExprMode or constVariantParam then` it skips the
whole lvalue CHAIN — `.ident` pairs, `^`, balanced `[...]` — and then judges by
the token that follows. For `o.m(math.pi)` the skip consumes `.pi`, the next
token is `)`, so the predicate does **not** answer True, the bare-lvalue arm
runs `FindSym('math')` = -1, and `ParseLValueAST` halts on the MODULE name.

**The second pass of this ticket was right that the argument is read twice and
that the first reading succeeds** — and that is exactly why the fix is here and
not at the error site. `PyParseFactorCore` resolves this correctly through
`ConsumeUnitQualifier` (unit 651, `pi` at TokPos 38). Adding a unit door at the
error site would have duplicated a door that already answered; the job was to
stop the bare-lvalue arm claiming the tokens at all.

**This is the third instance of one family in this one predicate.** Its own
trailing comments cite
`bug-p-a-parameterless-function-is-undefined-as-a-method-call-argument` and
`bug-p-a-parameterless-method-is-undefined-as-a-by-ref-argument` — same symptom
shape (`undefined variable` naming something that is not a variable), same
method-only asymmetry, same `FindSym < 0` gate, both fine through a free
function, because a free function reaches `ParseArgExpr` unconditionally. The
new clause sits beside them and is gated identically.

### Why the root-only test is safe, and why it is not wider than that

The clause tests the ROOT and the presence of a following `.ident`; it does not
inspect the member. A Pascal unit VARIABLE is a genuine by-ref target, so that
looks too broad — and is not, because of the gate it is under. `PyExprMode` is
false while an `.npy` program's Pascal RTL units are parsed, and a
`const Variant` parameter is never a binding target (the gate's own comment).
Measured rather than argued: a module variable (`ui.ROW`) and a module function
(`ui.wide()`) both give CPython's answer, and a local rebound to a module's own
name (`math = [1,2,3]; o.one(math)`) still takes the bare-lvalue parse for free,
because by then `FindSym` finds it and the gate excludes the clause.

The neighbouring clause carries a warning that was honoured here: ungating it
*"let a call RESULT bind to a genuine `var` parameter and the program COMPILED"*.
Nothing was ungated.

### Verified

- `make compiler/pascal26` — `converged after 1 round(s)`, `a1d4b73c63f5`.
- `test/test_nilpy_module_attr_method_arg.npy`, 11 rows, byte-identical to
  CPython. Rows MODQ / CALL / FIRST / LAST / KW / FREE / WRAPPED / NILPYVAR /
  NILPYFUNC / SHADOW; `math` covers `FindUnitOrAlias`'s plain arm and the
  aliased import its alias arm.
- **Positive control**: the pinned compiler answers
  `pascal26:26: error: undefined variable (math)` on row MODQ. The fixture can
  fail.
- FREE and WRAPPED are rows that already compiled, kept so a clause widened past
  the method path reds visibly instead of passing.
- lekkerzeilen closure **2959 -> 3215** (+256). New wall, separate ticket:
  `Variant :=: this scalar type not yet supported`.

### Corrections to this ticket's own earlier passes

- It said *"eleven `ParseLValueAST` call sites, all in `pasparser_lval.inc`"*.
  There are **43**, across `pasparser_lval.inc`, `pasparser_expr.inc` and
  `pyparser.inc`; the count came from grepping one file. The four that matter are
  the method-argument sites (`pyparser.inc:45483, 45638, 46588, 46666`), and
  none of them was the fix — the predicate they all consult was.
- The first pass concluded the unit door *"is not consulted here"*. It is, and it
  succeeds; corrected in the second pass and restated above.

## Log
- 2026-09-12 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
