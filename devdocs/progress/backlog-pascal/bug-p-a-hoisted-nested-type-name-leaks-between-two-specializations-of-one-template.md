---
track: P
prio: 55
type: bug
blocked-by: []
status: open
summary: "The hoist table is GLOBAL and single-slot, so a method-implementation header scanned for one specialization reads the hoisted names of whichever specialization ran LAST. `TOwner<T>` with a nested `PT = ^T` used as a generic argument, specialized on LongInt and Byte, mints `TPtrs$LongInt$TOwner$Byte$PT` — LongInt's method header paired with BYTE's hoisted PT — then fails `unknown type` on the name it just invented. 21-line repro, fpc 3.2.2 runs it. ONE instantiation is green, which is why every hoisting test written so far passes: the defect needs a SECOND specialization of the same template and no existing test has one."
---

# A hoisted nested-type name leaks between two specializations of one template

**The 21-line repro. fpc 3.2.2 compiles and runs it, printing `a 1 1`.**

```pascal
program dbl;
{$mode delphi}
type
  TPtrs<T, P> = class
    Q: P;
    function Width: Integer;
  end;
  TOwner<T> = class
  public type
    PT = ^T;
  public
    function Ptrs: TPtrs<T, PT>;
  end;
function TPtrs<T, P>.Width: Integer; begin Result := SizeOf(P); end;
function TOwner<T>.Ptrs: TPtrs<T, PT>; begin Result := nil; end;
var li: TOwner<LongInt>; by: TOwner<Byte>;
begin
  li := TOwner<LongInt>.Create;
  by := TOwner<Byte>.Create;
  WriteLn('a ', Ord(li.Ptrs = nil), ' ', Ord(by.Ptrs = nil));
end.
```

Measured on `c8ba1d666f79` (`3a89c6184`), `PXXDBG=p.mint:*`:

```
p.mint deferred alias=TPtrs$LongInt$TOwner$LongInt$PT  tmpl=TPtrs args=LongInt TOwner$LongInt$PT
p.mint deferred alias=TPtrs$Byte$TOwner$Byte$PT        tmpl=TPtrs args=Byte    TOwner$Byte$PT
p.mint late     alias=TPtrs$LongInt$TOwner$Byte$PT     tmpl=TPtrs args=LongInt TOwner$Byte$PT
pascal26:15: error: unknown type: TPtrs$LongInt$TOwner$Byte$PT
  near: ; function TOwner$LongInt . Ptrs : >>> TPtrs$LongInt$TOwner$Byte$PT ; begin
```

**The first two rows are correct and the third is the defect.** Both
specializations mint their own pair properly. Then line 15 — the METHOD
IMPLEMENTATION header, which is one token range in the stream shared by every
specialization — is scanned again and pairs `LongInt` with **Byte's** hoisted
`PT`.

## The mechanism

`HoistName`/`HoistFull`/`HoistUsed` (`pasparser_generic.inc:253`) are a single
global table. `CollectHoistCandidates` **resets it** (`HoistCount := 0`) at the
top of every `ParseSpecialization`, filling `HoistFull[k] := specName + '$' +
nm` for the specialization being parsed right now.

`NestedSpecArg` (`:420`) is the only reader — it calls `HoistedNameFor(nm)` and
writes the answer straight into `NSpecArg`, so the answer is baked in at SCAN
time and is correct for whatever the table held then. The bug is not the read;
it is **when the scan happens**. A method-implementation range is scanned after
a later specialization has already reset and refilled the table, so the name
that gets baked in belongs to the wrong specialization.

That is a real cross-specialization leak, not a naming cosmetic: the minted
alias names a type that is never declared, so the error is `unknown type` on a
name the compiler invented itself — which is why it reads like a mangler bug
and is not one.

## Why nothing caught it

**ONE instantiation is green.** Change `var by: TOwner<Byte>` to
`TOwner<LongInt>` and the program compiles and runs. Every hoisting test in
`test/` instantiates each template once, so the whole set passes while the
defect is live. The trigger is a SECOND specialization of the same template,
and a test asserting only that "a nested type works as a generic argument" can
never reach it. **`test_generic_nested_type_identity`, `..._field_name` and
`test_a_class_nested_type_is_a_specialization_argument` are all single-
instantiation and all green throughout.**

Any fix here needs a two-instantiation row with **different pointee types** —
give both the same argument and the two hoisted names coincide, and the test
prints the right answer while reading the wrong row.

## Provenance and what it blocks

Found while extending `CollectHoistCandidates` up the ANCESTOR chain for
`bug-p-a-class-nested-type-as-a-specialization-argument-resolves-at-unit-scope`
(door C, the rtl-generics rung). The extension is NOT the cause and that was
checked rather than assumed: the repro above fails identically on `c8ba1d666f79`,
which does not contain it, and on the door-C binary. **It is a pre-existing
door-B defect that the ancestor walk merely makes reachable from more places.**

It blocks a clean two-instantiation regression test for that ticket, and it is
in the path of any real generic container corpus, where one template is
specialized many times by construction.

## Where to start

The read is already resolved eagerly and correctly; the fix belongs at the
SCAN, not at `HoistedNameFor`. Either the hoist table must be keyed by
specialization rather than reset per parse, or every range belonging to a
specialization must be scanned inside that specialization's own window. The
second is the smaller claim and matches the existing comment at
`ScanRangeForNestedSpecs` about method bodies being buffered separately —
that arm was added because a range was being missed; this is the same arm
being scanned at the wrong time.
