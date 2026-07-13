{ An overloaded method's BODY must not clobber a different overload's table entry.

  When the implementation header could not be matched back to its declaration by proc
  identity, the binder fell back to a NAME match — which is the FIRST entry of that name,
  i.e. almost always a DIFFERENT overload — and overwrote its proc.

  fpjson's TJSONArray declares `Insert(Index)` plus ten `Insert(Index, ...)` overloads.
  Each two-arg body that missed the by-proc lookup landed on the ONE-arg entry and
  clobbered it, so `J.Insert(0)` could no longer find a one-argument Insert: the arity
  search fell through to a two-arg overload and the parser demanded a second argument
  ("expected ," at the closing paren).

  The name fallback now refuses to bind to an entry whose proc has a different arity.

  Expected output is FPC's. }
program test_method_overload_arity_rebind_b315;
{$mode objfpc}{$H+}

type
  TBag = class
  private
    FLog: string;
  public
    procedure Ins(Index: Integer);
    procedure Ins(Index: Integer; I: Integer);
    procedure Ins(Index: Integer; const S: string);
    procedure Ins(Index: Integer; B: Boolean);
    procedure Ins(Index: Integer; D: Double);
    property Log: string read FLog;
  end;

{ Implemented in a DIFFERENT order from the declarations, and the one-arg overload LAST —
  the shape that maximises the chance of a stale name-match clobbering it. }
procedure TBag.Ins(Index: Integer; const S: string);
begin
  FLog := FLog + 'str(' + S + ')';
end;

procedure TBag.Ins(Index: Integer; B: Boolean);
begin
  if B then FLog := FLog + 'bool(T)' else FLog := FLog + 'bool(F)';
end;

procedure TBag.Ins(Index: Integer; D: Double);
begin
  FLog := FLog + 'dbl';
end;

procedure TBag.Ins(Index: Integer; I: Integer);
begin
  FLog := FLog + 'int';
end;

procedure TBag.Ins(Index: Integer);
begin
  FLog := FLog + 'one';
end;

var
  B: TBag;
begin
  B := TBag.Create;
  B.Ins(0);              { must reach the ONE-argument overload }
  B.Ins(1, 42);
  B.Ins(2, 'x');
  B.Ins(3, True);
  B.Ins(4, 1.5);
  writeln(B.Log);
  B.Free;
end.
