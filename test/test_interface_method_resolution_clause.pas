program imrc;
{$mode objfpc}
{ `function IFoo.SomeMethod = MyImpl;` — a METHOD RESOLUTION CLAUSE in a class
  body. It declares nothing; it redirects one interface SLOT to a differently
  named method of the class.

  The two-interface rows are the point. A class implementing IAlpha and IBeta
  when both declare `Execute` has no other way to give them different bodies —
  a single `Execute` must serve both — so this is not sugar for anything.

  ORDER IS ASSERTED DELIBERATELY: the clause for TLate names an implementing
  method declared BELOW it, which is legal and is why the clause is recorded by
  NAME and resolved at the IMT build rather than bound where it is parsed.
  Reversing that would compile a test written the other way round and still be
  broken for real code. }
type
  IAlpha = interface function Execute: LongInt; end;
  IBeta  = interface function Execute: LongInt; end;

  { one interface, redirected name }
  IFoo = interface function SomeMethod: LongInt; end;
  TFoo = class(TInterfacedObject, IFoo)
    function IFoo_SomeMethod: LongInt;
    function IFoo.SomeMethod = IFoo_SomeMethod;
  end;

  { TWO interfaces whose method names collide — the case with no alternative }
  TBoth = class(TInterfacedObject, IAlpha, IBeta)
    function AlphaExec: LongInt;
    function BetaExec: LongInt;
    function IAlpha.Execute = AlphaExec;
    function IBeta.Execute = BetaExec;
  end;

  { the clause precedes the method it names }
  TLate = class(TInterfacedObject, IFoo)
    function IFoo.SomeMethod = LateImpl;
    function LateImpl: LongInt;
  end;

function TFoo.IFoo_SomeMethod: LongInt; begin Result := 42; end;
function TBoth.AlphaExec: LongInt;      begin Result := 1; end;
function TBoth.BetaExec: LongInt;       begin Result := 2; end;
function TLate.LateImpl: LongInt;       begin Result := 9; end;

var f: IFoo; a: IAlpha; b: IBeta; both: TBoth;
begin
  f := TFoo.Create;
  write('one=', f.SomeMethod);
  { BOTH references are taken from the OBJECT, not by casting one interface to
    the other. `IBeta(a)` is a hard reinterpret of an unrelated interface type:
    fpc keeps IAlpha's table and answers 1, pxx re-resolves and answers 2, and
    neither is this test's subject. Taking each reference from the instance is
    the defined route and the two compilers agree on it. }
  both := TBoth.Create;
  a := both;
  b := both;
  write(' alpha=', a.Execute, ' beta=', b.Execute);
  f := TLate.Create;
  writeln(' late=', f.SomeMethod);
end.
