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
    procedure Bump;                { protected METHOD: descendants + same unit }
  public
    procedure Init(v: integer);
    function SumWith(other: TNode): integer;   { another instance, same class -> ok }
    function Tag: integer;
    property Level: integer read FLevel;   { public property over a protected field }
  private
    procedure Note;                { private METHOD: whole declaring unit }
  end;

  TLeaf = class(TNode)
  public
    procedure Grow;                { descendant calls inherited protected method }
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

procedure TNode.Bump;
begin
  FLevel := FLevel + 1;
end;

procedure TNode.Note;
begin
  FVal := FVal + 100;
end;

procedure TLeaf.Grow;
begin
  Bump;                            { inherited protected method from descendant -> ok }
end;

var a, b: TNode; lf: TLeaf;
begin
  a := TNode.Create; a.Init(3);
  b := TNode.Create; b.Init(4);
  writeln(a.SumWith(b));           { 7 }
  writeln(a.Tag);                  { 30 }
  writeln(a.FVal);                 { 3 — private, but main IS the declaring unit }
  a.Note;                          { private METHOD, same unit -> ok }
  a.Bump;                          { protected METHOD, same unit -> ok }
  lf := TLeaf.Create; lf.Grow;
  writeln(lf.Level);               { 1 — public property over a protected field }
end.
