---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`TakeVal(TFoo.Create)` and `TakeVal(IFoo(o))` are refused with `by-reference argument must be a variable`, for both by-value and `const` interface parameters, while the same call with a named variable or an ordinary function result compiles. FPC accepts all four. Passing a freshly constructed object straight into a call is a common idiom, so this rejects working FPC code at compile time."
status: done
owner: claude-A
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

## Resolution (2026-08-21)

Done the way the ticket's root-cause note asked: **inverted, not extended**. The
five-armed disjunction is gone and one predicate replaces it, in `symtab.inc`:

```pascal
function ByRefArgNeedsLvalue(procIdx, argNo: Integer): Boolean;
begin
  Result := ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + argNo] and
            not ProcParamIsConst[procIdx * MAX_PROC_PARAMS + argNo];
end;
```

That is the whole rule. Everything else reaching the guard is by-ref for the ABI
only — a >8-byte record the callee copies, a `const Variant` boxed into a hidden
temp, a promo int copied with `PXXPromoCopy`, a fixed-array result already in a
caller-owned scratch — so the argument HAS an address and no write-back is
expected. The question never depended on the argument's type kind, which is
exactly why a constructor-call node (CLASS kind) and an `IFoo(o)` cast node (no
kind) could not be covered by any length of list.

**The two copies had already diverged**, which is the confirmation the note was
right: `pasparser_stmt.inc`'s overloaded-call twin never learned the promo-int
arm, so `f(g())` for a promotable-int parameter was accepted at one call site
and refused at the other. Both now call the one predicate.

### Measured against FPC 3.2.2 (`-O- -Mobjfpc`), both directions

Accepted — `test/test_byref_arg_lvalue_rule.pas`, **12/12 on pxx and 12/12 on
FPC**, same values. The four rows that were refused before are
`TakeVal(TFoo.Create)`, `TakeConst(TFoo.Create)`, `TakeVal(IFoo(o))`,
`TakeConst(IFoo(o))`; the other eight are the shapes that already worked plus
the four aggregates whose special cases the one rule replaced.

(FPC needs `uses variants` to RUN the `const Variant` row — without it that row
dies with runtime error 217. pxx's variant support is built in. Compile-time
acceptance, which is what this ticket is about, is identical either way.)

Refused — five `var`/`out` shapes, all still refused by pxx and all refused by
FPC:

| shape | pxx | FPC |
| --- | --- | --- |
| `var TBig` ← call result | refused | `Can't take the address of constant expressions` |
| `out TBig` ← call result | refused | same |
| `var Integer` ← literal | refused | `Variable identifier expected` |
| `var IFoo` ← `TFoo.Create` | refused | `Can't take the address of constant expressions` |
| `var IFoo` ← call result | refused | same |

`test/test_byref_arg_lvalue_refused.pas` pins one of them (the interface +
constructor shape) as a must-fail row; there is one code path now, so the other
four reach the same line.

### Noted, not touched

`ParseCallArg` in `pasparser_lval.inc:3316` is a **third** copy of this guard —
`if CurTok.Kind <> tkIdent then Error(...)`, the crudest version of all — and it
has no callers anywhere in the compiler. Left alone rather than deleted: it is
unreachable, so it cannot be wrong, and removing dead code is not this ticket.
Whoever next touches that file should delete it.

## Gate

`tools/gate.sh quick` GREEN (self-host fixedpoint 110s). Both new tests wired
into the core list: 12/12 accepted, and the `var` refusal asserted with
`! $(COMPILER)` plus a grep for the message — the widening direction is what
that row exists to catch. Corpus breadth is Track T's, against this sha.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
