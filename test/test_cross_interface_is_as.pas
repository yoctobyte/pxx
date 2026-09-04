program test_cross_interface_is_as;
{ `obj is IFoo` and `obj as IFoo` -- the INTERFACE arm of IRLowerClassMatch,
  which is the only thing in the language that emits IR_VMTADDR.

  THE CLASS ARM DOES NOT, and that is the whole reason this file exists rather
  than a class-hierarchy one. ir.inc's IRLowerClassMatch has two halves: for a
  CLASS target it walks the RTTI at runtime through a call (open-world, so a
  subclass declared in a later unit is still matched), and for an INTERFACE
  target it enumerates every implementing class's VMT address at codegen and
  compares. Only the second reaches IR_VMTADDR. Measured 2026-09-04 against pin
  v403: a `TB is TA` / `TB is TC` probe compiles and answers correctly on
  wasm32 with NO IR_VMTADDR arm present at all, so a class probe is a guard
  that cannot fail for this op.

  `onlyalpha is IBeta` is the row that must say FALSE. Every other row here is
  TRUE, and an arm that returned any constant address -- or the wrong class's --
  would still print TRUE for those: a set of all-TRUE rows cannot separate a
  working type test from one that always matches.

  Compared against the x86-64 build of this same source, not a literal, so no
  row here carries a hand-written answer that could be edited green. }
type
  IAlpha = interface ['{11111111-1111-1111-1111-111111111111}']
    procedure Alpha;
  end;
  IBeta = interface ['{22222222-2222-2222-2222-222222222222}']
    procedure Beta;
  end;
  TOnlyAlpha = class(TInterfacedObject, IAlpha)
    procedure Alpha;
  end;
  TBoth = class(TInterfacedObject, IAlpha, IBeta)
    procedure Alpha;
    procedure Beta;
  end;
procedure TOnlyAlpha.Alpha; begin writeln('  OnlyAlpha.Alpha'); end;
procedure TBoth.Alpha;      begin writeln('  Both.Alpha'); end;
procedure TBoth.Beta;       begin writeln('  Both.Beta'); end;

var
  oa: TOnlyAlpha; bo: TBoth; o: TObject; ia: IAlpha; ib: IBeta;
begin
  oa := TOnlyAlpha.Create;
  bo := TBoth.Create;

  o := oa;
  writeln('onlyalpha is IAlpha ', o is IAlpha);
  writeln('onlyalpha is IBeta  ', o is IBeta);   { the one FALSE row }

  o := bo;
  writeln('both is IAlpha      ', o is IAlpha);
  writeln('both is IBeta       ', o is IBeta);

  { The cast, both interfaces, and a call through each -- an `as` that picked
    the wrong VMT would still hand back a non-nil interface and dispatch into
    the wrong method rather than trapping, so the METHOD NAME is the assertion,
    not the fact that the cast returned. }
  o := bo;
  ia := o as IAlpha; ia.Alpha;
  ib := o as IBeta;  ib.Beta;

  o := oa;
  ia := o as IAlpha; ia.Alpha;

  ia := nil; ib := nil;
  writeln('done');
end.
