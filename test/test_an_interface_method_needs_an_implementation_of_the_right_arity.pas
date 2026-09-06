{ A class claiming an interface must implement each method with the right
  number of parameters — and the refusal must be the SAME for the plain
  spelling and for a method resolution clause.

  `IFoo = interface function M(a: LongInt): LongInt; end;` implemented by a
  class whose `M` takes NO argument compiled clean, and `f.M(1)` through the
  interface called the 0-argument body. fpc refuses the class.

  THE CAUSE WAS A HANDOFF BETWEEN TWO CORRECT-LOOKING PIECES, not a missing
  check in either. FindUMethForSig prefers an exact signature and falls back to
  the first NAME match — deliberately, so an implementation differing only
  cosmetically keeps binding — and its own comment hands the refusal to "the IMT
  builder's diagnostic". The IMT builder does make that diagnostic, but only
  when NO method of the name exists at all. So an arity mismatch was refused by
  nobody. Each half is defensible alone and the pair had a hole.

  THE CHECK IS ON ARITY AND NOT ON THE WHOLE SIGNATURE, and rows B and C are
  why. The fallback's tolerance is load-bearing: a parameter type that differs
  only cosmetically must still bind, and an overloaded interface method must
  still reach the class method of the matching shape. A count cannot be
  cosmetic, so refusing on arity alone refuses exactly what fpc refuses and
  leaves the tolerance intact.

  ROW E IS THE ONE THE CALL SITE WARNED ABOUT IN ADVANCE: a resolution clause
  rewrites the method name and reaches the same lookup, so a check written
  inside the clause branch would make `function IFoo.M = MyM` stricter than the
  plain same-named spelling it desugars to — a second divergence wearing the
  shape of a fix. The check sits at the shared line, and E asserts the two
  spellings refuse alike.

  Positive rows A-D are fpc 3.2.2 -Mobjfpc's own values. The refusal rows are
  compile-time and live in the Makefile beside this file, because a program that
  must not compile cannot assert from inside itself.
  bug-p-the-imt-signature-fallback-hands-off-a-refusal-nobody-makes }
program test_an_interface_method_needs_an_implementation_of_the_right_arity;
{$mode objfpc}
type
  TInt = LongInt;
  IFoo = interface function M(a: LongInt): LongInt; end;
  IThing = interface
    function Pick(x: LongInt): LongInt;
    function Pick(x, y: LongInt): LongInt;
  end;

  { A — the ordinary exact match }
  TExact = class(TInterfacedObject, IFoo) function M(a: LongInt): LongInt; end;
  { B — a COSMETIC difference: the parameter is an alias of the same type.
    This is what the name fallback exists for and it must keep binding. }
  TAlias = class(TInterfacedObject, IFoo) function M(a: TInt): LongInt; end;
  { C — an OVERLOADED interface method: each slot must reach the class method
    of its own arity, which is the defect FindUMethForSig was written for. }
  TPick = class(TInterfacedObject, IThing)
    function Pick(x: LongInt): LongInt; overload;
    function Pick(x, y: LongInt): LongInt; overload;
  end;
  { D — implemented by an INHERITED method rather than one declared here }
  TBase = class(TInterfacedObject) function M(a: LongInt): LongInt; end;
  TDeriv = class(TBase, IFoo) end;

var fails: Integer = 0;

procedure Chk(const what: string; got, want: LongInt);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

function TExact.M(a: LongInt): LongInt; begin Result := a + 1; end;
function TAlias.M(a: TInt): LongInt; begin Result := a + 2; end;
function TPick.Pick(x: LongInt): LongInt; begin Result := 100 + x; end;
function TPick.Pick(x, y: LongInt): LongInt; begin Result := 200 + x + y; end;
function TBase.M(a: LongInt): LongInt; begin Result := a * 2; end;

var f: IFoo; t: IThing;
begin
  f := TExact.Create;  Chk('A exact signature',        f.M(41),      42);
  f := TAlias.Create;  Chk('B alias parameter type',   f.M(40),      42);
  t := TPick.Create;   Chk('C overload slot 1',        t.Pick(1),    101);
                       Chk('D overload slot 2',        t.Pick(1, 2), 203);
  f := TDeriv.Create;  Chk('E inherited implementation', f.M(21),    42);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('IMTARITY OK');
end.
