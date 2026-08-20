program test_generic_inherit_delphi;
{ mode-Delphi twin of test_generic_inherit.pas. The surface differs -- no
  `generic`/`specialize` keywords -- but there must be only ONE resolver behind
  it: DelphiRewriteGenericUses rewrites `TBase<T>` into `specialize TBase<T>`
  wherever it is a TYPE reference, and drops the `<T>` only on a method
  IMPLEMENTATION header (`function TBase<T>.Get`), which is the one place it
  means "this template's own methods". }
{$mode delphi}{$H+}
type
  TBox<T> = class
    V: T;
    function Get: T;
  end;

  TCounted<T> = class(TBox<T>)
    N: Integer;
    function Bump: T;
  end;

  TTagged<T> = class(TCounted<T>)
    function Twice: T;
  end;

  TPairOf<K, D> = class
    A: K;
    B: D;
  end;

  THolder<K, D> = class(TPairOf<K, D>)
    function SumA: K;
  end;

  TWrap<T> = class
    Inner: TBox<T>;
    function Peek: T;
  end;

function TBox<T>.Get: T;
begin
  Result := V;
end;

function TCounted<T>.Bump: T;
begin
  Inc(N);
  Result := Get;
end;

function TTagged<T>.Twice: T;
begin
  Result := Get + Get;
end;

function THolder<K, D>.SumA: K;
begin
  Result := A + A;
end;

function TWrap<T>.Peek: T;
begin
  Result := Inner.Get;
end;

var
  t: TTagged<Integer>;
  s: TBox<AnsiString>;
  h: THolder<Integer, Integer>;
  w: TWrap<Integer>;
begin
  t := TTagged<Integer>.Create;
  t.V := 5;
  WriteLn('chain ', t.Get, ' ', t.Bump, ' ', t.Twice, ' ', t.N);

  s := TBox<AnsiString>.Create;
  s.V := 'plain';
  WriteLn('plain ', s.Get);

  h := THolder<Integer, Integer>.Create;
  h.A := 3; h.B := 4;
  WriteLn('pair ', h.SumA, ' ', h.B);

  w := TWrap<Integer>.Create;
  if w.Inner = nil then WriteLn('wrap nil') else WriteLn('wrap set');
  WriteLn('GENERIC INHERIT DELPHI OK');
end.
