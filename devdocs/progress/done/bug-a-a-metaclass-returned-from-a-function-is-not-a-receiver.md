---
track: A
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
---

# A metaclass returned from a FUNCTION is not a receiver

- **Type:** bug (wrong refusal, with an internal-sounding message) — **Track A**
- **Split from** [[bug-a-a-metaclass-typed-record-field-is-not-a-receiver]],
  which fixed the FIELD spelling of the same family.
- **Pre-existing.**

```pascal
type TBaseClass = class of TBase;
function Give: TBaseClass; begin Result := TDer; end;
begin WriteLn(Give.Kind); end.
```

FPC prints `der`. pxx:

    IR_UNSUPPORTED: frontend could not lower AST node (kind 8) — a frontend gap,
    would miscompile

## Why it is a different fix from the field one

The field case lives in `ParseLValueAST`'s metaclass-receiver list. A CALL
result does not reach that list at all: `ApplyCallResultPtrSuffix` sees a
typed-pointer return (`ProcRetPtrElemTk` = `tyClass`) and walks `^` / `[i]` /
`.field` over it with the record-field builder — so `.Kind`, a class METHOD,
becomes an `AN_FIELD`, which lowering then cannot handle. Hence the internal
message rather than a diagnostic.

The fix is to notice, in `ApplyCallResultPtrSuffix`, that the pointee is a
CLASS and hand off to the metaclass machinery (`ci` = `ProcRetPtrElemRec` -
`REC_UCLASS_BASE`) instead of the field walker — the same handoff the other
three base kinds already make.

**Do not add a fifth ad-hoc arm without looking at the whole family first.**
Four sites now decide "is this a metaclass value?" by base node kind
(`AN_IDENT`, `AN_PTR_CAST`, `AN_INDEX`, `AN_FIELD`), plus this one in a
different function. One predicate — `NodeMetaclassCi(node): Integer` — would
replace all of them and is very likely the smaller change; see
[[project_record_field_and_selector_resolution_landmines]] and
`devdocs/dev/normalise-dont-special-case.md`.

## Gate

`Give.Kind`, `Give.ClassName` and `Give.Create` matching FPC, the four existing
spellings still green (`test/test_metaclass_field_receiver.pas`), self-host
byte-identical.

## Resolution (2026-08-11)

Took the ticket's own advice and did the family first: **`NodeMetaclassCi(node)`
now answers "which class does this node's metaclass value refer to?" for all
five spellings** — `class of T` variable (`Syms[].PtrElem*`), inline metaclass
cast (`AliasElem*`), element of an array of them (the ARRAY symbol's
`PtrElem*`), metaclass-typed field (`UFldPtrElem*`), and the one that was
missing, a function RESULT (`ProcRetPtrElem*`). ParseLValueAST's four inline
copies collapse into one call to it.

The call-result spelling additionally never reached that list: the suffix after
a call is walked by `ApplyCallResultPtrSuffix`, a different function, which saw
a typed-pointer return and built an `AN_FIELD` over a class reference — hence
the internal `IR_UNSUPPORTED` message instead of a diagnostic. It now asks
`NodeMetaclassCi` first and dispatches the member the same three ways the
ParseLValueAST arm does: a class-reference operation (`ClassName`/`ClassType`/
`InheritsFrom`, via `GenMakeClassRefOp` + `ParseClassRefOpTail`), a CONSTRUCTOR
(`BuildMetaclassNew`, so the virtual ctor dispatches on the dynamic class), or a
class METHOD (`GenMakeStaticMethodCall` with the metaclass value as Self). An
instance method through a class reference now gets a real diagnostic.

Diffed against `fpc -O1` and matching on x86-64 and all four cross targets:
`Give.Kind`, `Give.ClassName`, `Give.Create` (virtual dispatch — `BDB`), a
metaclass-returning function WITH arguments (`Pick(0)` / `Pick(1)`), and the
four control spellings still green. Family sweep of the 48 `test/*.pas` matching
metaclass|classref|class_of|rtti|virtual|ctor against `pinned`: no behaviour
change; the five that do not compile are negative tests, refused identically on
`pinned`.

New `test/test_metaclass_call_receiver.pas`.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
