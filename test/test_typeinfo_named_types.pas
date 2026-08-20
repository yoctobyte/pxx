program test_typeinfo_named_types;
{ TypeInfo(T) over the NAMED types the alias table carries: subranges, sets,
  procedural types, method pointers, string[N], and a plain rename.

  Every kind here was `TypeInfo is not supported for type: ...` before
  feature-typeinfo-all-types. The kinds are FPC's TTypeKind ordinals, measured
  against FPC 3.2.2 rather than recalled — 1 tkInteger, 5 tkSet, 6 tkMethod,
  7 tkSString, 23 tkProcVar.

  The NAME is the half that is easy to get wrong. FPC's rule is that a DISTINCT
  type carries its own typeinfo, so `TSub = 1..10` reports `TSub` — but the
  plain rename `TMyInt = Integer` is NOT distinct and reports the BASE type's
  name, not `TMyInt`. We approximate distinctness by structure (an alias that
  DEFINES something keeps its name), which reproduces every measured case.

  We report `Integer` where FPC reports `LongInt` for that last one: pxx's
  tyInteger and tyInt32 are separate kinds where FPC's Integer IS LongInt, and
  TypeInfoOrdName's one-canonical-spelling-per-tk choice predates this test.
  Asserted as-is deliberately — see decide-typeinfo-scalar-name-spelling. }
uses typinfo;
type
  TSub   = 1..10;
  TEnum  = (eA, eB, eC);
  TSet   = set of TEnum;
  TProc  = procedure(x: Integer);
  TMeth  = procedure(x: Integer) of object;
  TStr20 = string[20];
  TMyInt = Integer;
procedure Show(p: PTypeInfo);
begin
  Writeln(p^.NamePtr^, ' ', p^.Kind);
end;
begin
  Show(TypeInfo(TSub));
  Show(TypeInfo(TSet));
  Show(TypeInfo(TProc));
  Show(TypeInfo(TMeth));
  Show(TypeInfo(TStr20));
  Show(TypeInfo(TMyInt));
end.
