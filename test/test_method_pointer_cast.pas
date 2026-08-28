{ A cast to a METHOD-POINTER type reads a bare `obj.M` as a REFERENCE, not a call.

  Delphi lets the `@` be omitted where a method pointer is wanted, so `obj.M`
  means two different things and only the context separates them. An assignment
  whose LHS is a method-pointer variable supplied that context; a CAST whose
  target is a method-pointer TYPE did not, so `TSel(s.IPick)` was parsed as a
  zero-argument call and the returned integer was reinterpreted as a
  {Code, Data} pair -- which segfaulted.

  Both receiver flavours are pinned because they are one concept reached two
  ways: a VARIABLE (Self is the instance) and a CLASS NAME (Self is the
  metaclass -- the RTTI blob, whose VMT lives at +24 rather than [Self+0]).
  The class arm is the one the rtl-generics corpus reaches.

  Output verified against FPC 3.2.2.
  bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults }
program test_method_pointer_cast;
{$MODE DELPHI}{$H+}
type
  TSel = function(A: LongInt): LongInt of object;
  TSvc = class
    function IPick(A: LongInt): LongInt;
    class function CPick(A: LongInt): LongInt;
    function VPick(A: LongInt): LongInt; virtual;
  end;
  TDer = class(TSvc)
    function VPick(A: LongInt): LongInt; override;
  end;

function TSvc.IPick(A: LongInt): LongInt; begin Result := A * 3; end;
class function TSvc.CPick(A: LongInt): LongInt; begin Result := A * 2; end;
function TSvc.VPick(A: LongInt): LongInt; begin Result := A + 1; end;
function TDer.VPick(A: LongInt): LongInt; begin Result := A + 1000; end;

var
  s: TSvc;
  d: TDer;
  m: TSel;
begin
  s := TSvc.Create;
  d := TDer.Create;

  m := TSel(s.IPick);      WriteLn('inst  ', m(5));
  m := TSel(TSvc.CPick);   WriteLn('class ', m(5));

  { the cast must not defeat virtual dispatch: through a TSvc-typed
    reference to a TDer, the override has to win }
  s := d;
  m := TSel(s.VPick);      WriteLn('virt  ', m(5));

  { and an ordinary call still means what it did. `m := @s.VPick` is NOT here
    on purpose: FPC rejects the plain address-of an INSTANCE method ("Variable
    identifier expected") while we accept it -- CLAUDE.md's "we accept a form
    FPC rejects" row, a divergence rather than a defect. It cannot be pinned in
    a test whose expectations come from the FPC oracle. }
  WriteLn('call  ', TSvc(d).IPick(4));
end.
