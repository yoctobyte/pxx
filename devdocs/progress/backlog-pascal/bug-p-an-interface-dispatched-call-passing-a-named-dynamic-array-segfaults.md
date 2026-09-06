---
slug: bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults
track: P
type: bug
prio: 55
status: done
created: 2026-09-06
found-by: frankB
owner: frankB
blocked-by: []
title: "A NAMED array-type parameter was recorded as a scalar by all four method parsers; an implementation header repaired it, so only interface and `abstract` methods showed it"
summary: "CLOSED PENDING-COMMIT. THE SLUG SAYS INTERFACE AND THE CAUSE IS NOT INTERFACE DISPATCH. The four parameter parsers in pasparser_decl.inc (record method, proc-type signature, interface method, class method) knew only the LITERAL `array of` spelling; a NAMED array type -- `TDyn = array of Integer`, `TFix = array[0..2] of Integer` -- fell to ParseTypeKind, which collapses it to a scalar, so the row recorded IsArray = False and the ELEMENT kind as the parameter's own. ParseSubroutine has had that arm since named fixed arrays worked. A CLASS OR RECORD METHOD IS DECLARED TWICE -- in the body, and again by its implementation header, which goes through ParseSubroutine and OVERWRITES the row -- so the wrong row was written for every method in the language and repaired for every method with a body in the same unit. The two spellings with no implementation header are an INTERFACE method and `virtual; abstract`, and those are the only places it survived to a call site. `b.Dy(d)` through a plain class reference to an abstract method fails identically, with no interface anywhere, which is the measurement that separates the cause from the report. Symptoms: `no overload of Dy matches these arguments` for a variable argument (the single-candidate probe in FindUMethOverloadAhead skips IsArray parameters and this one was not one, so it asked MatchParamAccepted with the ELEMENT kind), and compiled-then-SEGFAULTED for `nil` (argIsNil skips the same check, and the call then marshalled a dynamic array as a scalar). FIXED by ParamNamedArrayType, one shared arm called from all four parsers, plus the dynamic-DEPTH column threaded through the three method parsers' durable param rows -- IsArray alone left `var a: TDyn` through an interface compiling and segfaulting, because a var dynamic array needs the by-ref HANDLE ABI. STILL MISSING and stated rather than implied: the fixed length/low bound, N-D dims and element-row geometry that ParseSubroutine also records have no channel in the three method parsers, so a named FIXED array parameter of an interface or abstract method keeps the open-array ArrLen=1000 placeholder -- right for reading, indexing and High(), wrong for a whole-array assignment inside the callee. Twelve rows against fpc 3.2.2, contents not length, with `abstract` and `nil` rows labelled for what each can and cannot show."
---

# A named array-type parameter was a scalar wherever no implementation header repaired it

```pascal
type
  TDyn = array of Integer;
  TBase = class
    procedure Dy(a: TDyn); virtual; abstract;   { no implementation header }
  end;
var b: TBase; d: TDyn;
begin
  b := TSub.Create; SetLength(d, 3);
  b.Dy(d);      { pxx: no overload of Dy matches these arguments.  fpc: fine }
end.
```

**No interface anywhere.** The ticket was filed against interface dispatch
because that is where it was first seen, and the abstract-method row above is
what says the report named a symptom.

## The cause

The four parameter parsers in `pasparser_decl.inc` — `ParseRecordMethodDecl`,
`ParseProcTypeSignature`, and the interface- and class-method arms of
`ParseTypeSection` — each wrote

```pascal
mIsArr := False;
if CurTok.Kind = tkArray then begin Next; Expect(tkOf,'of'); ...; mIsArr := True; end
else mTk := ParseTypeKind;
```

`ParseTypeKind` collapses a named array type to a scalar, so the row got
`IsArray = False` and `TypeKind` = the ELEMENT kind — the field's other meaning,
recorded under the wrong one
([[refactor-p-a-parameters-own-kind-and-its-element-kind-are-one-field-and-the-name-says-neither]]).
`ParseSubroutine` (`pasparser_proc.inc`) has had the `FindArrayType` arm since
named fixed-array parameters were made to work, and the method parsers never
grew it.

**A method is declared twice.** The class body writes the row; the
implementation header goes through `ParseSubroutine` and overwrites it. So the
defect was present for every method in the language and repaired for every method
with a body in the same unit. It survives in exactly two spellings — an
**interface** method, which has no implementation header at all, and
**`virtual; abstract`**, which has none either. Same shape as
[[bug-p-a-default-value-is-accepted-on-an-open-array-parameter]], where the
interface method was likewise the one nobody asked.

## Why one spelling was refused and the other crashed

`FindUMethOverloadAhead`'s single-candidate probe (`pasparser_call.inc`) reads:

```pascal
if Procs[pi].Params[pj].IsArray then continue;   { array param: no type question }
if ProcParamUntyped[...] then continue;
if argIsNil[j] then continue;
if not MatchParamAccepted(pi, pj, argTk[j]) then ok := False;
```

With `IsArray = False` the parameter is asked about by TYPE, and the type on
record is the element kind — so a dynamic-array argument is refused. `nil` skips
the same check on the line below, which is why the ticket's original repro
compiled and then segfaulted: it reached the call with a scalar marshalling for a
dynamic array.

## The fix, and the part of it that IsArray alone did not buy

`ParamNamedArrayType` — one arm, called from all four parsers — consumes the type
name and answers with the element kind, the pointee and the dynamic depth.

`IsArray` alone fixed the refusal and the `const` crash, and left `var a: TDyn`
through an interface compiling and segfaulting: a `var` dynamic array needs the
by-ref HANDLE ABI, which keys off `ProcParamDynDepth`, a column the three method
parsers never wrote at all. Threaded through, including both Self-shift loops —
a column added to a shift loop and not its sibling is the defect that block's own
comments already record.

## What is still missing, stated rather than implied

`ParseSubroutine`'s arm also records the fixed LENGTH and low bound, the N-D
dimensions, and the element-row geometry for an open array of named rows. The
three method parsers have no channels for any of it. So a named FIXED array
parameter of an interface or abstract method still carries the open-array
`ArrLen := 1000` placeholder: correct for reading, indexing and `High()`, which
is what the fixture asserts, and wrong for a whole-array assignment inside the
callee (`bug-array-assign-to-var-param`'s shape, one declaration site over).
Filling those is the rest of the job and wants the durable-param-row treatment
rather than three more columns bolted on.

## The sibling, resolved

[[bug-p-an-interface-dispatched-call-that-omits-a-defaulted-argument-segfaults]]
was filed beside this one with the independence explicitly NOT established, and
the honest answer is now measured: **they do not share a cause.** That one was a
missing default-argument FILL in four call-site arms; this one is a parameter
ROW written wrong at declaration time. Fixing that one did not fix this one — it
was re-measured still crashing at that commit — and fixing this one does not
touch defaults.

## Log
- 2026-09-06 — cause located and fixed; resolved, commit PENDING-COMMIT.
