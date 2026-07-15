program test_member_visibility;
{$mode objfpc}
{ Member visibility: parsed always, enforced only under --strict-visibility.
  This program uses only ACCESSES that are valid under FPC semantics, so it
  compiles under BOTH the lax default AND --strict-visibility. Regression that
  the enforcement does not false-positive on valid code. }
type
  TNode = class
  private
    FVal: integer;                 { unit-scoped: the whole program unit sees it }
  strict private
    FTag: integer;                 { type-scoped: only TNode's own methods }
  protected
    FLevel: integer;
  public
    procedure Init(v: integer);
    function SumWith(other: TNode): integer;   { another instance, same class -> ok }
    function Tag: integer;
  end;

procedure TNode.Init(v: integer);
begin
  FVal := v;                       { own private, own method -> ok }
  FTag := v * 10;                  { own strict private -> ok }
  FLevel := 1;
end;

function TNode.SumWith(other: TNode): integer;
begin
  SumWith := FVal + other.FVal;    { other instance's private, same class -> ok }
end;

function TNode.Tag: integer;
begin
  Tag := FTag;
end;

var a, b: TNode;
begin
  a := TNode.Create; a.Init(3);
  b := TNode.Create; b.Init(4);
  writeln(a.SumWith(b));           { 7 }
  writeln(a.Tag);                  { 30 }
  writeln(a.FVal);                 { 3 — private, but main IS the declaring unit }
end.
