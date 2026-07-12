---
prio: 42
---

# Builtin TObject class — `var o: TObject` + `TObject.Create` + root methods

- **Type:** feature (Pascal frontend — builtin class) — **Track P/A**
- **Status:** backlog — filed 2026-07-12 (conformance sweep + Pascal Script).

## Symptom

`TObject` works as a PARAMETER type (tyPointer/elem tyClass, landed
bug-tobject-param-truncated-32bit) and as an implicit class PARENT
(`class(TObject)` — parent resolution special-cases it). But there is no real
TObject class ROW, so:

```pascal
var o: TObject;
begin
  o := TObject.Create;   { undefined variable (TObject) }
  writeln(o.GetHashCode);
end.
```

fails. Blocks tobject5, tclassinfo1 (also needs RTTI ClassInfo), and any
real-world code using a bare `TObject` instance (very common — Pascal Script,
Synapse hooks, LCL).

## Fix shape

Mirror RegisterBuiltinTGuid (a builtin record minted at ParseProgram start),
but as a CLASS: a zero-field TObject with a VMT, a `Create` constructor
(GetMem instance + stamp VMT + return), and `Free`/`Destroy` (the obj.Free
desugar already exists). FPC's TObject also has Equals/GetHashCode/ClassName/
UnitName/InstanceSize — add the simple ones (GetHashCode = PtrInt(self),
Equals = pointer compare); ClassName/UnitName/ClassInfo need RTTI (defer /
separate ticket).

The tricky part vs TGuid: a class needs a VMT slot table + a constructor
proc with a synthesized body. Look at how metaclass New / GenMakeFreeObject
build instances for the allocation shape.

## Gate

`make test` + self-host byte-identical; a compile-run test
(`var o: TObject; o := TObject.Create; o.Free`); unskip tobject5 (partial —
the RTTI-free assertions).
