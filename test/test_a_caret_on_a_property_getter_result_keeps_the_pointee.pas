{ A CARET ON A PROPERTY GETTER'S RESULT KEEPS THE POINTEE'S SHAPE.
  `c.L^[1]` over `property L: PIA read GetL` (PIA = ^array of Integer) read
  element 2: the instance property arm dereferenced a getter result with its
  own loop, which tagged every deref Int64 and dropped the pointee, so the
  subscript stepped 8 bytes whatever the element. 50 where FPC reads 30, a
  Word array read 0 -- on every target. TList's `list.List^[i]` is the same
  shape, and was right on 64-bit only because a Pointer is 8 bytes; on i386,
  arm32 and riscv32 it read the wrong slot (lib_classes' list-List-alias row).
  The method spelling `c.GetL^[1]`, a parenthesised `(c.L)^[1]`, a cast and a
  field-backed property were always right.
  Expected output is FPC 3.2.2's, generated, not written.
  bug-p-a-caret-on-a-property-getter-result-indexes-in-8-byte-steps }
program test_a_caret_on_a_property_getter_result_keeps_the_pointee;
{$mode objfpc}
type
  TIA = array[0..7] of Integer;   PIA = ^TIA;
  TWA = array[0..7] of Word;      PWA = ^TWA;
  TBA = array[0..7] of Byte;      PBA = ^TBA;
  TQA = array[0..7] of Int64;     PQA = ^TQA;
  TDA = array[0..7] of Double;    PDA = ^TDA;
  TPA = array[0..7] of Pointer;   PPA = ^TPA;
  TR = record a: Byte; b: Integer; end;
  TRA = array[0..7] of TR;        PRA = ^TRA;
  PTR = ^TR;
  PPInt = ^PInteger;
  TC = class
    i: TIA; w: TWA; b: TBA; q: TQA; d: TDA; p: TPA; r: TRA; one: TR;
    n: Integer; pn: PInteger;
    function GI: PIA; function GW: PWA; function GB: PBA; function GQ: PQA;
    function GD: PDA; function GP: PPA; function GR: PRA; function GOne: PTR;
    function GPP: PPInt; function GRaw: Pointer;
    property I_: PIA read GI; property W_: PWA read GW; property B_: PBA read GB;
    property Q_: PQA read GQ; property D_: PDA read GD; property P_: PPA read GP;
    property R_: PRA read GR; property One_: PTR read GOne;
    property PP_: PPInt read GPP; property Raw_: Pointer read GRaw;
  end;
function TC.GI: PIA; begin Result := @i; end;
function TC.GW: PWA; begin Result := @w; end;
function TC.GB: PBA; begin Result := @b; end;
function TC.GQ: PQA; begin Result := @q; end;
function TC.GD: PDA; begin Result := @d; end;
function TC.GP: PPA; begin Result := @p; end;
function TC.GR: PRA; begin Result := @r; end;
function TC.GOne: PTR; begin Result := @one; end;
function TC.GPP: PPInt; begin Result := @pn; end;
function TC.GRaw: Pointer; begin Result := @n; end;
var c: TC; k: Integer;
begin
  c := TC.Create;
  for k := 0 to 7 do
  begin
    c.i[k] := 10 + k; c.w[k] := 20 + k; c.b[k] := 30 + k; c.q[k] := 40 + k;
    c.d[k] := 0.5 + k; c.p[k] := Pointer(PtrInt(50 + k));
    c.r[k].a := 60 + k; c.r[k].b := 70 + k;
  end;
  c.one.a := 1; c.one.b := 2; c.n := 99; c.pn := @c.n;
  WriteLn('Integer ', c.I_^[1], ' ', c.I_^[5]);
  WriteLn('Word    ', c.W_^[1], ' ', c.W_^[5]);
  WriteLn('Byte    ', c.B_^[1], ' ', c.B_^[5]);
  WriteLn('Int64   ', c.Q_^[1], ' ', c.Q_^[5]);
  WriteLn('Double  ', c.D_^[1]:0:2, ' ', c.D_^[5]:0:2);
  WriteLn('Pointer ', PtrInt(c.P_^[1]), ' ', PtrInt(c.P_^[5]));
  WriteLn('record  ', c.R_^[1].a, ' ', c.R_^[1].b, ' ', c.R_^[5].b);
  k := 3;
  WriteLn('var idx ', c.I_^[k], ' ', c.W_^[k], ' ', c.R_^[k].b);
  c.I_^[2] := 1234; c.W_^[2] := 4321; c.R_^[2].b := 777;
  WriteLn('written ', c.i[2], ' ', c.w[2], ' ', c.r[2].b, ' ', c.i[3], ' ', c.w[3]);
  WriteLn('rec ptr ', c.One_^.a, ' ', c.One_^.b);
  WriteLn('ptr ptr ', c.PP_^^);
  WriteLn('untyped ', Integer(c.Raw_^));
  c.Free;
end.
