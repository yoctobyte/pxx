unit uopcirca;

{ Half of the CIRCULAR implementation-`uses` pair. uopcirca's interface declares
  an operator on TCA; its implementation uses uopcircb, whose implementation uses
  uopcirca back. Compiling uopcircb therefore happens while uopcirca's
  implementation section is still pending, so the interface DECLARATION is the
  only thing that can have registered the operator by then.
  bug-p-an-operator-declared-in-a-unit-interface-is-not-registered-until-its-body-is-parsed }

interface

type
  TCA = record
    x, y: LongInt;
  end;

operator + (const a, b: TCA) c: TCA;
{ The ARITY PAIR, and it is the positive control for the name scheme: a unary
  and a binary `-` agree on opKey, on both operand type names (the right one is
  read off the LAST colon) and on the result type. Only the parameter count
  separates them, so without arity in the synthesised name these two collide
  into one proc and the second body overwrites the first. }
operator - (const a, b: TCA) c: TCA;
operator - (const a: TCA) c: TCA;

procedure UseBsOperator;

implementation

uses uopcircb;

operator + (const a, b: TCA) c: TCA;
begin
  c.x := a.x + b.x;
  c.y := a.y + b.y;
end;

operator - (const a, b: TCA) c: TCA;
begin
  c.x := a.x - b.x;
  c.y := a.y - b.y;
end;

operator - (const a: TCA) c: TCA;
begin
  c.x := -a.x;
  c.y := -a.y;
end;

procedure UseBsOperator;
var p, q, r: TCB;
begin
  p.x := 44; p.y := 67;
  q.x := -34; q.y := -57;
  r := p + q;
  WriteLn('A body, B operator : ', r.x, ' ', r.y);
end;

end.
