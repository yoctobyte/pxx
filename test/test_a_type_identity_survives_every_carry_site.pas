program test_a_type_identity_survives_every_carry_site;
{ A type's identity -- what it MEANS, when its TTypeKind carries only how it is
  LAID OUT -- has to survive every place a declaration can be written down, not
  just a plain `var`. Each row below is one carry site named by
  decide-how-a-type-carries-an-identity-its-kind-cannot-hold, and each one lost
  it independently: a symbol, a record field, a parameter, a function result and
  the alias table.

  BOTH FAMILIES on every row. An enum (tyInteger plus an id, identity >= 0) and
  a sized boolean (an integer of its own width, identity negative) travel the
  same channels, and the fallback tests inside NodeSemIdOf were `< 0` -- correct
  while enums were the only family and silently discarding the other. Two of
  these rows were green for enums and red for booleans at the same commit, which
  is the reason the pairing is the assertion and not decoration.

  .expected is fpc 3.2.2's own output. }
type
  TCol = (cRed, cGreen, cBlue);
  TFlag = LongBool;                  { the alias table }
  TRec = record e: TCol; b: ByteBool; end;

var
  r: TRec; fl: TFlag; ec: TCol; bb: ByteBool;

function FEnum: TCol;   begin Result := cGreen; end;
function FBool: LongBool; begin Result := True; end;

procedure PEnum(e: TCol);    begin WriteLn('param  ', e); end;
procedure PBool(b: ByteBool); begin WriteLn('param  ', b, ' ord=', Ord(b), ' not=', not b); end;

begin
  { 1 -- the SYMBOL itself }
  ec := cBlue; bb := True;
  WriteLn('sym    ', ec);
  WriteLn('sym    ', bb, ' ord=', Ord(bb), ' not=', not bb);

  { 2 -- a RECORD FIELD }
  r.e := cGreen; r.b := True;
  WriteLn('field  ', r.e);
  WriteLn('field  ', r.b, ' ord=', Ord(r.b), ' not=', not r.b);

  { 3 -- a PARAMETER. The identity is read from the durable ProcParamSemId row
    and NOT from the param symbol, whose slot is recycled across procs. }
  PEnum(cRed);
  PBool(True);

  { 4 -- a FUNCTION RESULT. Two halves and neither is sufficient: the callee's
    `Result` needs the identity to store the right bits, and the CALLER's node
    needs it to render -- a call node has no symbol and no field, so
    ProcRetSemId is the only place it survives. }
  WriteLn('ret    ', FEnum);
  WriteLn('ret    ', FBool, ' ord=', Ord(FBool), ' not=', not FBool);

  { 5 -- the ALIAS TABLE. `type TFlag = LongBool` is the boolean twin of
    `type TDays = D`, and the alias column stores identity +1 so that a row
    nobody wrote reads as NONE rather than as identity 0. That bias still works
    unchanged for a negative family, because no real identity is -1. }
  fl := True;
  WriteLn('alias  ', fl, ' ord=', Ord(fl), ' not=', not fl);
end.
