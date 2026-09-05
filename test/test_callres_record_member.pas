{ A member that is NOT a field, reached through a call result, is what
  ParseClassRecordSelectors resolves — and ApplyCallResultPtrSuffix's suffix
  loop was the one postfix walker of five that never reached it. Its `.name`
  arm goes straight to RequireRecMember, which knows only fields, so a method
  or a property was rejected outright:

    GetP^.Doubled     "Doubled": no such member on this record/class
    GetP^.Bump(1)     same
    GetP^.V           same  (a record property)
    GetP^.V := 7      same

  FOUR OTHER OPENERS spell the same member on the same record and all four were
  correct throughout, on the pinned compiler too: a.Doubled, vp^.Doubled,
  PRec(q)^.Doubled, TRec(a).Doubled. That is the control saying the divergence
  is the OPENER.

  The record id was never the problem: a plain field through the same chain
  (GetP^.v) has always resolved, which it could not if the pointee's record id
  were empty here. Only the escape was missing.

  Found by the escape census in refactor-p-three-hand-rolled-postfix-loops.
  Expected output is fpc 3.2.2 -Mdelphi -O1. }
program test_callres_record_member;
type
  PInt = ^Integer;
  PRec = ^TRec;
  TRec = record
  private
    fv: Integer;
    function GetProp: Integer;
    procedure SetProp(n: Integer);
  public
    v: Integer;
    pi: PInt;
    function Doubled: Integer;
    procedure Bump(n: Integer);
    property P: Integer read GetProp write SetProp;
  end;
var
  a: TRec;
  vp: PRec;
  q: Pointer;
  iv: Integer;
function TRec.GetProp: Integer; begin GetProp := fv * 10; end;
procedure TRec.SetProp(n: Integer); begin fv := n + 1; end;
function TRec.Doubled: Integer; begin Doubled := v * 2; end;
procedure TRec.Bump(n: Integer); begin v := v + n; end;
function GetP: PRec; begin GetP := @a; end;
begin
  a.v := 21; a.fv := 4; iv := 42; a.pi := @iv;
  vp := @a; q := @a;

  { the four openers that always worked — the control }
  WriteLn('plain=', a.Doubled);
  WriteLn('vardrf=', vp^.Doubled);
  WriteLn('ptrcast=', PRec(q)^.Doubled);
  WriteLn('reccast=', TRec(a).Doubled);

  { the one that did not }
  WriteLn('callfn=', GetP^.Doubled);
  WriteLn('callprop=', GetP^.P);
  GetP^.Bump(1);
  WriteLn('callproc=', a.v);
  GetP^.P := 7;
  WriteLn('callset=', a.fv);

  { fields through the same opener must be unaffected }
  WriteLn('callfld=', GetP^.v);
  WriteLn('calldrf=', GetP^.pi^);
  GetP^.pi^ := 9;
  WriteLn('callstore=', iv);

  WriteLn('CALLRES RECORD MEMBER OK');
end.
