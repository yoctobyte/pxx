program test_open_array_param_slot_is_a_handle;
{ An open-array parameter occupies ONE pointer-sized slot, whatever its element
  type -- the slot holds a handle, and `array of Double` records tyDouble in the
  parameter only because that is the ELEMENT's kind.

  Three places on i386 re-derived that rule instead of asking the ABI oracle
  (ABIParamSlotIsPointer, which ParamSize and AllocParam already both read), and
  all three widened a 64-bit-element open array to eight bytes. The caller ran
  cvtsi2sd over the dyn-array handle and pushed the double bits; the callee's
  spill copied eight bytes into a four-byte slot and clobbered the neighbour;
  and the width walk that computes every EARLIER parameter's [ebp+disp] shifted
  them all by four. So `LD(d)` faulted before its first statement, `H1(b: Int64;
  const a: array of Double)` came back with b's high dword set, and
  `H4(b: Double; const a: array of Double; c: Integer)` lost b entirely.

  Ordering matters here and is the point of the mixed rows: a bad slot width is
  invisible when the open array is the LAST parameter and corrupts a different
  neighbour depending on what precedes it.

  Every expected line is fpc 3.2.2's own output. }
type
  TIA = array of Integer;
  TI64 = array of Int64;
  TSiA = array of Single;
  TDA = array of Double;
  TBA = array of Byte;
  TRec = record a: Integer; b: Integer; end;
  TRA = array of TRec;

function LI(const a: array of Integer): Integer; begin Result := Length(a); end;
function L64(const a: array of Int64): Integer; begin Result := Length(a); end;
function LSi(const a: array of Single): Integer; begin Result := Length(a); end;
function LD(const a: array of Double): Integer; begin Result := Length(a); end;
function LB(const a: array of Byte): Integer; begin Result := Length(a); end;
function LR(const a: array of TRec): Integer; begin Result := Length(a); end;

{ the open array is not the last parameter, so a bad width shifts a neighbour }
function H1(b: Int64; const a: array of Double): Int64; begin Result := Length(a) + b; end;
function H2(b: Double; const a: array of Integer): Double; begin Result := Length(a) + b; end;
function H3(b: Double; const a: array of Double; c: Integer): Double; begin Result := b + Length(a) + c; end;
function H4(const a: array of Double; b: Double; c: Double): Double; begin Result := b + Length(a) + c; end;
function H5(const a: array of Int64; b: Int64): Int64; begin Result := Length(a) + b; end;
function H6(b: Double; const a: array of Double): Double; begin Result := Length(a) + b; end;

{ by-value (not const), and a var parameter next to an open array }
function V1(a: array of Double): Double;
var i: Integer;
begin Result := 0; for i := 0 to High(a) do Result := Result + a[i]; a[0] := 999; end;
function V2(var r: Double; const a: array of Single): Double;
var i: Integer;
begin r := 100; Result := r; for i := 0 to High(a) do Result := Result + a[i]; end;

var i: TIA; q: TI64; si: TSiA; d: TDA; b: TBA; r: TRA; rr: Double;
begin
  SetLength(i,2); SetLength(q,2); SetLength(si,2); SetLength(b,2); SetLength(r,2);
  SetLength(d,3); d[0]:=1.5; d[1]:=2.25; d[2]:=3.0;
  si[0]:=0.5; si[1]:=1.5;
  q[0]:=10; q[1]:=20;
  WriteLn('len int   : ', LI(i));
  WriteLn('len int64 : ', L64(q));
  WriteLn('len single: ', LSi(si));
  WriteLn('len byte  : ', LB(b));
  WriteLn('len rec   : ', LR(r));
  WriteLn('len double: ', LD(d));
  WriteLn('H1        : ', H1(7, d));
  WriteLn('H2        : ', H2(0.5, i):0:1);
  WriteLn('H3        : ', H3(0.5, d, 2):0:1);
  WriteLn('H4        : ', H4(d, 0.5, 0.25):0:2);
  WriteLn('H5        : ', H5(q, 4));
  WriteLn('H6        : ', H6(0.5, d):0:1);
  WriteLn('V1        : ', V1(d):0:3, ' d0=', d[0]:0:2);
  WriteLn('V2        : ', V2(rr, si):0:3, ' r=', rr:0:1);
end.
