---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`TakeVal(TFoo.Create)` and `TakeVal(IFoo(o))` are refused with `by-reference argument must be a variable`, for both by-value and `const` interface parameters, while the same call with a named variable or an ordinary function result compiles. FPC accepts all four. Passing a freshly constructed object straight into a call is a common idiom, so this rejects working FPC code at compile time."
status: backlog
owner: unassigned
---

# A non-lvalue is refused as an interface argument

- **Track A** — the guard is in the SHARED `compiler/parser.inc` (~line 16353),
  so it is edited under A's gate and must not be touched concurrently with A.
- Found 2026-08-20 by an FPC differential probe of the interface/ARC surface,
  alongside `bug-a-an-interface-passed-by-value-leaks-a-reference-per-call`.

## Measured

`fpc -O- -Mobjfpc` vs pxx at `35b69f6e3`. `TakeVal(a: IFoo)`,
`TakeConst(const a: IFoo)`, `o: TFoo`, `MakeFoo: IFoo`.

| argument | FPC | pxx |
| --- | --- | --- |
| `TakeVal(o)` — class variable | OK | OK |
| `TakeConst(o)` | OK | OK |
| `f := o; TakeVal(f)` | OK | OK |
| `TakeVal(MakeFoo)` — function result | OK | OK |
| `TakeConst(MakeFoo)` | OK | OK |
| **`TakeVal(TFoo.Create)`** — constructor result | OK | **error** |
| **`TakeConst(TFoo.Create)`** | OK | **error** |
| **`TakeVal(IFoo(o))`** — explicit cast | OK | **error** |

`error: by-reference argument must be a variable`.

Note it is NOT the class→interface conversion: a class VARIABLE passes fine. It
is specifically a non-lvalue in an interface parameter position.

## Cause

The by-ref argument guard admits a non-lvalue only through an explicit list of
alternatives, and the one that would cover this tests
`IntToTypeKind(ASTTk[exprNode]) = tyRecord`. An interface value is modelled as a
tyRecord, which is why an ordinary function result returning `IFoo` gets through
— but a constructor call node carries the CLASS type kind, and an explicit
`IFoo(o)` cast node carries neither, so both miss the list.

## Root-cause note — this guard is now a design flaw by the repo's own rule

The same condition has been extended once per aggregate kind:

- `bug-a-promoint-parameter-rejects-literals-and-call-results`
- `bug-a-a-fixed-array-call-result-is-refused-as-a-const-byref-argument`
- the `const Variant` boxing alternative
- the by-value/`const` record alternative
- and now interfaces

That is five arms of one disjunction, each added after a user hit it.
`devdocs/dev/root-cause-over-microfix.md` says two is a smell and three is a
design flaw. **Do not add a sixth arm.** The question the guard actually wants to
answer is "will IRLowerCallArg materialise a temp with an address for this
argument?" — which is knowable from the parameter mode plus whether the param is
a genuine `var`/`out`, and does not need to enumerate type kinds at all. Invert
it: refuse a non-lvalue only for an EXPLICIT `var`/`out` parameter (where FPC
refuses it too, including for a call result), and accept it everywhere else.

Doing that would close this ticket and delete the four existing special cases in
the same change — measure it in tickets-closed-per-change, not lines touched.

## Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. Because
the inversion widens what is ACCEPTED, the risk is a previously-rejected shape
now lowering to a bad address — cover `var`/`out` refusal explicitly in the test,
and let Track T sweep the corpora.
