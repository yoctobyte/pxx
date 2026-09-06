program test_forward_double_pointer_alias_order;
{$mode delphi}
{ `PP = ^P` written ABOVE `P = ^T` -- rtl-generics' own spelling. The repair
  pass that fixes forward pointee aliases ran ONCE, forward, so PP (the lower
  index) copied P's still-unrepaired REC_NONE base and was never revisited.

  Both orders are asserted, and that is the point: the SAME program with the two
  pointer rows swapped was already correct, so only a pair discriminates. Both
  fields of each record are read for the same reason -- the lost base made the
  field selector resolve at OFFSET 0, so `.a` (which IS at offset 0) stayed
  right and only `.b` read back `.a`. A one-field probe passes while broken. }
type
  PPFwd = ^PFwd;          { forward: pointee declared below }
  PFwd  = ^TFwd;
  TFwd  = record a, b: Integer; end;

  PBwd  = ^TBwd;          { control: the identical shape, rows swapped }
  PPBwd = ^PBwd;
  TBwd  = record a, b: Integer; end;

  PPPFwd = ^PPFwd2;       { three levels, all forward -- one pass repairs one }
  PPFwd2 = ^PFwd2;
  PFwd2  = ^TFwd2;
  TFwd2  = record a, b: Integer; end;
var
  rf: TFwd;  pf: PFwd;  ppf: PPFwd;
  rb: TBwd;  pb: PBwd;  ppb: PPBwd;
  r3: TFwd2; p3: PFwd2; pp3: PPFwd2; ppp3: PPPFwd;
  ok: Boolean;
begin
  ok := True;
  rf.a := 11; rf.b := 22; pf := @rf; ppf := @pf;
  rb.a := 33; rb.b := 44; pb := @rb; ppb := @pb;
  r3.a := 55; r3.b := 66; p3 := @r3; pp3 := @p3; ppp3 := @pp3;

  if ppf^^.a <> 11 then begin WriteLn('fwd.a=', ppf^^.a); ok := False; end;
  if ppf^^.b <> 22 then begin WriteLn('fwd.b=', ppf^^.b); ok := False; end;
  if ppb^^.a <> 33 then begin WriteLn('bwd.a=', ppb^^.a); ok := False; end;
  if ppb^^.b <> 44 then begin WriteLn('bwd.b=', ppb^^.b); ok := False; end;
  if ppp3^^^.a <> 55 then begin WriteLn('l3.a=', ppp3^^^.a); ok := False; end;
  if ppp3^^^.b <> 66 then begin WriteLn('l3.b=', ppp3^^^.b); ok := False; end;

  if ok then WriteLn('FWDPTRORDER OK') else WriteLn('FWDPTRORDER FAIL');
end.
