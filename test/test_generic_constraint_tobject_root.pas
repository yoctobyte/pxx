program test_generic_constraint_tobject_root;
{ `T: TObject` is the ROOT constraint and cannot be answered by walking
  UClsParent: pasparser_decl.inc deliberately leaves parentCi = -1 for BOTH
  `class(TObject)` and a plain `class`, because a real parent link would
  relocate every `class(TObject)` VMT and break the implicit-root model. TObject
  is nonetheless a registered builtin class ROW, so the constraint check found
  it and then walked a chain that structurally never reaches it.

  Only `specialize TBox<TObject>` passed, because argCi = conCi matched on the
  first iteration. EVERY descendant was rejected — implicit or explicit, same
  type section or not, one level or three.

  The section-splitting rows are here deliberately: the regression was first
  read as a type-section TIMING bug, and rows 2 and 5 are what falsify that.
  They must keep passing for the same reason they were written — a future
  timing-flavoured change would otherwise silently re-open the wrong diagnosis.

  regression-p-generic-constraint-check-rejects-a-class-declared-in-the-same-type-section }
{$mode objfpc}
type
  generic TBox<T: TObject> = class
    item: T;
  end;

  { 1: implicit TObject descendant, SAME type section as the specialization }
  TImplicit = class
    v: Integer;
  end;
  TBoxImplicit = specialize TBox<TImplicit>;

  { 2: explicit `class(TObject)`, same section }
  TExplicit = class(TObject)
    v: Integer;
  end;
  TBoxExplicit = specialize TBox<TExplicit>;

  { 3: three levels down }
  TMid  = class(TExplicit) end;
  TDeep = class(TMid) w: Integer; end;
  TBoxDeep = specialize TBox<TDeep>;

  { 4: TObject itself — the one shape that passed before the fix }
  TBoxObject = specialize TBox<TObject>;

{ 5: a SEPARATE type section — passed and failed identically before the fix,
  which is what proved the defect was not section timing }
type
  TLater = class
    v: Integer;
  end;
  TBoxLater = specialize TBox<TLater>;

{ 6: a USER base class as the constraint still walks the parent chain normally }
type
  generic TUBox<T: TExplicit> = class
    item: T;
  end;
  TUBoxDeep = specialize TUBox<TDeep>;

var
  bi: TBoxImplicit; be: TBoxExplicit; bd: TBoxDeep;
  bo: TBoxObject;   bl: TBoxLater;    bu: TUBoxDeep;
begin
  bi := TBoxImplicit.Create; bi.item := TImplicit.Create; bi.item.v := 1;
  be := TBoxExplicit.Create; be.item := TExplicit.Create; be.item.v := 2;
  bd := TBoxDeep.Create;     bd.item := TDeep.Create;     bd.item.w := 3;
  bo := TBoxObject.Create;   bo.item := TObject.Create;
  bl := TBoxLater.Create;    bl.item := TLater.Create;    bl.item.v := 5;
  bu := TUBoxDeep.Create;    bu.item := TDeep.Create;     bu.item.w := 6;
  WriteLn('implicit ', bi.item.v);
  WriteLn('explicit ', be.item.v);
  WriteLn('deep     ', bd.item.w);
  WriteLn('tobject  ', bo.item <> nil);
  WriteLn('later    ', bl.item.v);
  WriteLn('userbase ', bu.item.w);
end.
