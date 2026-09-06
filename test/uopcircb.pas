unit uopcircb;

{ The other half of the cycle — see uopcirca. }

interface

type
  TCB = record
    x, y: LongInt;
  end;

operator + (const a, b: TCB) c: TCB;

procedure UseAsOperator;

implementation

uses uopcirca;

operator + (const a, b: TCB) c: TCB;
begin
  c.x := a.x + b.x;
  c.y := a.y + b.y;
end;

procedure UseAsOperator;
var p, q, r: TCA;
begin
  p.x := 11; p.y := 22;
  q.x := 33; q.y := 44;
  r := p + q;
  WriteLn('B body, A operator : ', r.x, ' ', r.y);
end;

end.
