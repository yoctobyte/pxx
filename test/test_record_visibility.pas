program test_record_visibility;
{$mode objfpc}{$modeswitch advancedrecords}
{ Record member visibility: parsed always, enforced only under
  --strict-visibility. Every ACCESS here is valid under FPC semantics, so this
  compiles under BOTH the lax default AND --strict-visibility. The
  must-not-false-positive control for the record half of the flag, and drawn
  from the record population -- the class control cannot stand in for it, which
  is why the gap it covers went unseen. }
type
  TRec = record
  private
    FVal: integer;                 { unit-scoped: the whole program unit sees it }
  strict private
    FTag: integer;                 { type-scoped: only TRec's own methods }
  public
    procedure Init(v: integer);
    function Tag: integer;
    function SumWith(const other: TRec): integer;   { another instance, same type -> ok }
  end;

procedure TRec.Init(v: integer);
begin
  FVal := v;        { own private field, own method }
  FTag := v * 2;    { own strict private field, own method }
end;

function TRec.Tag: integer;
begin
  Tag := FTag;      { strict private read from inside the declaring type }
end;

function TRec.SumWith(const other: TRec): integer;
begin
  SumWith := FTag + other.FTag;   { another INSTANCE of the same type: legal }
end;

var a, b: TRec;
begin
  a.Init(3);
  b.Init(4);
  WriteLn(a.FVal);        { private, same unit -> legal }
  WriteLn(a.Tag);
  WriteLn(a.SumWith(b));
end.
