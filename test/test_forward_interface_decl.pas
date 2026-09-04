program test_forward_interface_decl;
{ `IFoo = interface;` — the FORWARD interface declaration.

  A double case with one arm missing. The CLASS arm has had this since forever
  (`UClsForward[ci] := (not hadParens) and (CurTok.Kind = tkSemicolon)`) and the
  interface arm never got it, so the parser walked into a body that is not there
  and asked for the `end` that is not coming: `expected 'end' before ';'` on
  line 4 of a six-line program. Pre-existing on pin v403 and on HEAD alike.
  bug-p-a-forward-interface-declaration-is-not-parsed

  THE FORWARD PAIR IS THE POINT, NOT THE PARSE. Accepting `interface;` and then
  registering a SECOND row for the real declaration would compile this file and
  be wrong in a way nothing here could see: FindUClass answers with the first
  match, so every later use would bind to the empty stub. Rows 1 and 2 are
  therefore not "it compiled" — they call a method THROUGH the interface and
  through the class, which only works if the stub was completed in place.

  Row 3 is the landmine the ticket predicted (credit frankwasm) and it is the
  reason this is not a one-line fix: specializing against a forward interface
  reaches the constraint checker, which walked a parent chain the stub does not
  have. `T: IInterface` is the exact mirror of `T: TObject`, which had the same
  bug for the same reason and is already fixed in the else-branch beside it.
  It is fpc-testsuite tgenconstraint37, %NORUN, the only test in that set that
  specializes a generic against forward-declared types.

  The negative half — that the DIRECTION still matters, and that a class stub
  and a record still fail an interface constraint — is
  test_forward_interface_constraint_fail.pas. It is a separate file because a
  refusal cannot share a program with the rows that must compile. }
{$mode objfpc}
type
  IFoo = interface;                  { forward interface }
  TBar = class;                      { forward class -- the arm that worked }

  generic TGenObj<T: TObject> = class v: T; end;
  generic TGenIntf<T: IInterface> = class v: T; end;
  TSpecObj  = specialize TGenObj<TBar>;
  TSpecIntf = specialize TGenIntf<IFoo>;

  IFoo = interface
    function Val: Integer;
  end;
  TBar = class(TInterfacedObject, IFoo)
    function Val: Integer;
  end;

function TBar.Val: Integer; begin Result := 42; end;

var b: TBar; i: IFoo; so: TSpecObj; si: TSpecIntf;
begin
  b := TBar.Create;
  i := b;
  WriteLn('through intf  ', i.Val);
  WriteLn('through class ', b.Val);
  so := TSpecObj.Create; so.v := b;
  si := TSpecIntf.Create; si.v := i;
  WriteLn('specialized   ', so.v.Val, ' ', si.v.Val);
end.
