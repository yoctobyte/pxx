program test_generic_inherit;
{ A generic class may name ANOTHER generic with its own type parameters -- as a
  base class, or as the type of a field. `TBase$T` is not a type, so what T is
  only becomes known when the OUTER generic is specialized; see the
  nested-specialization note in compiler/parser.inc. Delphi-surface twin:
  test_generic_inherit_delphi.pas. }
{$mode objfpc}{$H+}
type
  generic TBox<T> = class
    V: T;
    function Get: T;
  end;

  { one level: parameter forwarded to the base }
  generic TCounted<T> = class(specialize TBox<T>)
    N: Integer;
    function Bump: T;
  end;

  { two levels: the chain must unwind, each link declared before its child }
  generic TTagged<T> = class(specialize TCounted<T>)
    function Twice: T;
  end;

  { two parameters, both forwarded }
  generic TPairOf<K, D> = class
    A: K;
    B: D;
  end;

  generic THolder<K, D> = class(specialize TPairOf<K, D>)
    function SumA: K;
  end;

  { the same shape in a FIELD type rather than a base class }
  generic TWrap<T> = class
    Inner: specialize TBox<T>;
    function Peek: T;
  end;

function TBox.Get: T;
begin
  Result := V;
end;

function TCounted.Bump: T;
begin
  Inc(N);
  Result := Get;
end;

function TTagged.Twice: T;
begin
  Result := Get + Get;
end;

function THolder.SumA: K;
begin
  Result := A + A;
end;

function TWrap.Peek: T;
begin
  Result := Inner.Get;
end;

type
  TIntTagged = specialize TTagged<Integer>;
  TStrBox    = specialize TBox<AnsiString>;
  TIntHolder = specialize THolder<Integer, Integer>;
  TIntWrap   = specialize TWrap<Integer>;

var
  t: TIntTagged;
  s: TStrBox;
  h: TIntHolder;
  w: TIntWrap;
begin
  t := TIntTagged.Create;
  t.V := 5;
  WriteLn('chain ', t.Get, ' ', t.Bump, ' ', t.Twice, ' ', t.N);

  s := TStrBox.Create;
  s.V := 'plain';
  WriteLn('plain ', s.Get);

  h := TIntHolder.Create;
  h.A := 3; h.B := 4;
  WriteLn('pair ', h.SumA, ' ', h.B);

  { the nested generic FIELD exists and starts empty; naming its type
    portably is a separate matter (an alias would be a distinct
    specialization here), so only its presence is asserted }
  w := TIntWrap.Create;
  if w.Inner = nil then WriteLn('wrap nil') else WriteLn('wrap set');
  WriteLn('GENERIC INHERIT OK');
end.
