---
track: A
prio: 70
type: bug
blocked-by: []
status: done
owner: claude-A
commit: d0fcf625b
summary: "Adding `InstanceSize` to the TObject class-reference operation set broke every RTTI program: typinfo's TClassRTTI HAS an InstanceSize field, and the `obj.ClassName / obj.InheritsFrom(C)` arm never asked whether the receiver was a RECORD or whether it had a FIELD of that name. `cls^.InstanceSize` became __pxxRttiOf(cls^) — the record's first word read as an object's class pointer — and segfaulted. Resolves regression-test-core-test-rtti and regression-test-core-test-classref."
---

# A class-reference operation name hijacks a record field

Filed by the Track T watcher as `regression-test-core-test-rtti` and
`regression-test-core-test-classref` (both `Segmentation fault`, bad
`392ea5d94545`, last good `766e6ea5b4d6`). Re-verified at HEAD before acting;
both still red.

## Repro

```pascal
program rt1;
uses typinfo;
type TB = class private FId: Integer; published property Id: Integer read FId write FId; end;
var cls: PClassRTTI;
begin
  cls := GetClass('TB');
  Writeln('name: ', cls^.NamePtr^);      { TB   }
  Writeln('size: ', cls^.InstanceSize);  { SIGSEGV }
end.
```

`PXXDBG=a.ir` on the routine shows it plainly — instead of a field read at
offset 16 it emits `load_mem`, `load_mem`, `+8`, `load_mem`, then a call to
`__pxxInstanceSize`: the RECORD's first word was read as an object's class
pointer.

## Root cause

`5cdebf0f5` (TObject.InstanceSize and ClassNameIs) added two names to
`IsClassRefOpName`. The arm that answers them on an INSTANCE receiver
(`pasparser_lval.inc`, "obj.ClassName / obj.ClassType / obj.InheritsFrom(C)")
guarded only on

```pascal
(mmi < 0) and (mci >= 0) and IsClassRefOpName(fieldName)
```

— no METHOD of that name, and the receiver is a class-LIKE entry. Records are
class-like entries too (`UClsIsRecord`), and nothing asked about FIELDS.

That was harmless while the set was ClassName / ClassType / InheritsFrom /
ClassParent: nobody names a record field any of those. `InstanceSize` is a real
field of `typinfo.TClassRTTI` — the very record the RTTI API hands out — so the
new name landed exactly on the one collision the guard could not survive.

The two SIBLING sites already made both tests: the chained-value arm
(`(x as T).ClassName`) checks `FindUField(ci, ...) < 0` and
`not UClsIsRecord[ci]`, and the implicit-Self arm in `pasparser_expr.inc` checks
`FindUField` too. This arm was the one nobody went back for — the double-case
shape `devdocs/dev/normalise-dont-special-case.md` is about.

## The fix

Add the two tests this arm was missing, so all three sites ask the same
question: a record receiver never reaches a class-reference operation, and a
real field of the name outranks it.

## The siblings, checked before closing

The two neighbouring arms in the same function — `obj.GetInterface(IID, Obj)`
and `obj.MethodAddress(name)` / `obj.MethodName(addr)` — carry the identical
`(mmi < 0) and (mci >= 0)` guard with no record test. Both additionally require
a following `(`, so no field READ can reach them today; a proc-typed record
field called as `r.MethodAddress(x)` could. They are TObject operations and a
record has none of them, so the exclusion is added there too rather than left as
the next instance of this bug.

## Verified

`test/test_rtti.pas` and `test/test_classref.pas` both run to completion again
(28 and 3 lines, previously SIGSEGV after 2). New focused test
`test/test_a_record_field_named_like_a_class_operation.pas`, byte-identical to
`fpc -Mobjfpc -O1`: all four colliding names as record fields, read through the
variable AND through a pointer (the spelling that crashed), a write through the
pointer landing in the field, and a class with no member of the name still
reaching the operation — the row that proves the guard did not simply switch
the arm off.

Not asserted: a CLASS field of one of these names. FPC rejects that outright
(`Duplicate identifier "InstanceSize"`), so there is no oracle for the row; pxx
accepts it and the fix makes the field win, which is the sane direction.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
