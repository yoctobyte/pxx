{ A pointer alias declared inside a class or record body belongs to THAT type,
  not to the unit.

  `TA` and `TB` may each declare `type PCell = ^TCell; TCell = record ... end;`
  with DIFFERENT pointee types, and each must see its own. Before the owning-
  class column on the alias table they shared one flat row and the second
  declaration silently inherited the first's pointee, so `n^.d := v` in TB's
  method was type-checked against TA's field:

      error: incompatible types: cannot assign AnsiString to Integer

  and the direction of that message followed DECLARATION ORDER, which is what
  named the mechanism as a shared slot rather than a mis-parse.

  EVERY ROW USES TWO DIFFERENT POINTEE TYPES, DELIBERATELY. The cheapest way to
  write this test wrong is to give both classes an Integer pointee: it prints
  the right answer and cannot fail, because the value read from the WRONG row
  and the value read from the right one are the same. That variant was measured
  green throughout the entire bug. Wherever the unset or wrong value collides
  with a legal one, the guard cannot fail -- so Integer/AnsiString here, never
  Integer/Integer.

  The bug had NO generic in it. It was filed from a `specialize` repro and the
  specializer merely emits two ordinary class bodies, which is rows 1-2 below.

  Rows 3-4 are the two halves of the scope: a nested alias is named inside the
  class DECLARATION and again inside the out-of-line METHOD BODY, which are two
  separate source ranges carried by two different variables (ParsingClassBodyCi
  and MethImplOwnerCi). A fix that consulted only the first compiles the field
  declaration and then fails in the method, so both are asserted.

  Row 5 keeps a TOP-LEVEL alias of the same name reachable from outside any
  class -- the scoping must not make ordinary unit-level aliases invisible. }
{$mode objfpc}{$H+}
program test_nested_pointer_alias_is_scoped_to_its_owner;

type
  { a unit-level PCell, same name as both nested ones }
  TTopCell = record d: LongInt; end;
  PCell = ^TTopCell;

  TIntBox = class(TObject)
    type PCell = ^TCell; TCell = record d: Integer; end;
    var head: PCell;
    procedure Put(v: Integer);
    function Get: Integer;
  end;

  TStrBox = class(TObject)
    { DIFFERENT pointee type, SAME alias and pointee spellings }
    type PCell = ^TCell; TCell = record d: AnsiString; end;
    var head: PCell;
    procedure Put(v: AnsiString);
    function Get: AnsiString;
  end;

  { different ALIAS names, same pointee spelling -- b_diffptr }
  TRecA = record
    type PA = ^TCell; TCell = record d: Integer; end;
    var head: PA;
  end;
  TRecB = record
    type PB = ^TCell; TCell = record d: AnsiString; end;
    var head: PB;
  end;

  { same alias name, different POINTEE names -- c_diffcell }
  TThird = class(TObject)
    type PCell = ^TCellQ; TCellQ = record d: Double; end;
    var head: PCell;
    procedure Put(v: Double);
  end;

procedure TIntBox.Put(v: Integer);
var n: PCell;            { resolved in a METHOD BODY, not the class body }
begin New(n); n^.d := v; head := n; end;

function TIntBox.Get: Integer;
begin Get := head^.d; end;

procedure TStrBox.Put(v: AnsiString);
var n: PCell;
begin New(n); n^.d := v; head := n; end;

function TStrBox.Get: AnsiString;
begin Get := head^.d; end;

procedure TThird.Put(v: Double);
var n: PCell;
begin New(n); n^.d := v; head := n; end;

var
  i: TIntBox; s: TStrBox; t: TThird;
  ra: TRecA; rb: TRecB;
  top: PCell;            { the UNIT-level PCell, outside every class }
begin
  i := TIntBox.Create; s := TStrBox.Create; t := TThird.Create;
  i.Put(7);
  s.Put('hi');
  t.Put(2.5);
  WriteLn('1 int=', i.Get);
  WriteLn('2 str=', s.Get);
  WriteLn('3 dbl=', t.head^.d:0:1);

  New(ra.head); New(rb.head);
  ra.head^.d := 11;
  rb.head^.d := 'rec';
  WriteLn('4 reca=', ra.head^.d);
  WriteLn('5 recb=', rb.head^.d);

  New(top);
  top^.d := 99;
  WriteLn('6 top=', top^.d);
  WriteLn('OK');
end.
