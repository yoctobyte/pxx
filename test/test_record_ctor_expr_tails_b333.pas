{ Record-constructor results as full expressions (b333).

  Two separable gaps left over from feature-pascal-record-constructors:
  - `TPt.Create(1,2) + TPt.Create(10,20)` — operator-overload dispatch could
    not see a record-factory CALL node's record (a ctor proc has no return
    rec; the record lives on the hidden LIFTED temp — ResolveNodeRec now falls
    back to it).
  - `TPt.Create(7,8).Sum` — postfix selectors now chain on the factory result
    (the lifted temp is an addressable record).
  Verified against FPC. }
program test_record_ctor_expr_tails_b333;
{$mode objfpc}{$h+}

type
  TPt = record
    X, Y: Longint;
    constructor Create(ax, ay: Longint);
    function Sum: Longint;
    class operator + (const a, b: TPt): TPt;
  end;

constructor TPt.Create(ax, ay: Longint);
begin
  X := ax;
  Y := ay;
end;

function TPt.Sum: Longint;
begin
  Result := X + Y;
end;

class operator TPt.+ (const a, b: TPt): TPt;
begin
  Result.X := a.X + b.X;
  Result.Y := a.Y + b.Y;
end;

var
  r: TPt;
begin
  r := TPt.Create(1, 2) + TPt.Create(10, 20);
  Writeln('sum-op: ', r.X, ',', r.Y);
  Writeln('chain:  ', TPt.Create(7, 8).Sum);
  Writeln('both:   ', (TPt.Create(1, 1) + TPt.Create(2, 2)).Sum);
end.
