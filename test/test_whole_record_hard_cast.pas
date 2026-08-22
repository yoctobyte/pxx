program test_whole_record_hard_cast;
{ `TQ(r)` with no trailing accessor is a VALUE reinterpret, exactly like
  `TQ(r).field` — it used to stay a POINTER cast, so `q := TQ(r)` copied a
  record from whatever address r's first bytes spelled and segfaulted.
  Every row checked against fpc 3.2.2 -Mobjfpc -O1.
  bug-a-a-whole-record-hard-cast-is-lowered-as-a-pointer-cast }
type TR = record a, b: Integer; end;
     TQ = record x: Int64; end;
     PR = ^TR;
     TP = packed record a, b, c, d: Byte; end;
     TI = record v: Integer; end;
     TB = record b: array[0..7] of Byte; end;
var r: TR; q: TQ; pr_: PR; pp: Pointer;
    p1: TP; i1: TI; b1: TB; k: Integer;

procedure ByRef(const x: TI); begin WriteLn('byref ', x.v); end;
function MakeP: TP; begin Result.a := 1; Result.b := 0; Result.c := 0; Result.d := 0; end;

begin
  r.a := 1; r.b := 2;
  q := TQ(r);                 WriteLn('assign ', q.x);
  WriteLn('field  ', TQ(r).x);
  TQ(r).x := 7;               WriteLn('lvalue ', r.a, ' ', r.b);
  { the pointer path must stay the pointer path: `^` derefs the VALUE }
  pr_ := @r; pp := pr_;
  WriteLn('ptr    ', PR(pp)^.a);
  p1.a := 1; p1.b := 2; p1.c := 3; p1.d := 4;
  i1 := TI(p1);               WriteLn('p->i   ', i1.v);
  i1.v := $01020304;
  p1 := TP(i1);               WriteLn('i->p   ', p1.a, ' ', p1.b, ' ', p1.c, ' ', p1.d);
  for k := 0 to 7 do b1.b[k] := k + 1;
  q := TQ(b1);                WriteLn('b->q   ', q.x);
  ByRef(TI(p1));
  i1 := TI(MakeP);            WriteLn('call   ', i1.v);
end.
