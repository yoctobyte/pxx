program test_advanced_records_b268;
{ Advanced records: methods inside a record (FPC's {$modeswitch advancedrecords}). Its own
  RTL leans on this — TPoint / TSize / TRect in rtl/inc/typshrdh.inc are all advanced
  records — so nothing that includes them could fully parse before.

  A record method is an ordinary method whose implicit Self is the RECORD, passed BY
  REFERENCE. That by-ref is not a detail: a by-value Self would mutate a COPY and silently
  lose every write, which is exactly what the first attempt did (`p.SetX` left p unchanged).

  There is no VMT — records have no inheritance, so every call is static, which makes this
  far smaller than the class-method path.

  The subtle bit was the implicit-Self field access: that path hardcoded Self as tyClass, so
  a record Self was dereferenced as an object POINTER and the field access segfaulted. It
  now takes the symbol's real type. }
type
  TPt = record
    X, Y: Longint;
  public
    constructor Create(ax, ay: Longint);   { fills a FRESH receiver; no heap, no VMT }
    { FPC's advanced-record operator syntax. pxx keys an operator on its OPERAND TYPES, so
      the in-record signature carries nothing the definition does not — it is parsed and
      discarded, and the `class operator TPt.+` DEFINITION below is what registers it. }
    class operator + (const u, v: TPt): TPt;
    class operator = (const u, v: TPt): Boolean;
    procedure Init(ax, ay: Longint);
    procedure Offset(dx, dy: Longint);
    function Sum: Longint;
    function Add(const other: TPt): TPt;
  private
    function Half: Longint;
  end;

constructor TPt.Create(ax, ay: Longint);
begin
  X := ax;
  Y := ay;
end;

class operator TPt.+ (const u, v: TPt): TPt;
begin
  Result.X := u.X + v.X;
  Result.Y := u.Y + v.Y;
end;

class operator TPt.= (const u, v: TPt): Boolean;
begin
  Result := (u.X = v.X) and (u.Y = v.Y);
end;

function MakeAt(n: Longint): TPt;
begin
  MakeAt := TPt.Create(n, n * 2);   { a ctor result carried out as a function result }
end;

procedure TPt.Init(ax, ay: Longint);
begin
  X := ax;
  Y := ay;
end;

procedure TPt.Offset(dx, dy: Longint);
begin
  X := X + dx;          { must write THROUGH Self, not to a copy }
  Y := Y + dy;
end;

function TPt.Sum: Longint;
begin
  Sum := X + Y;
end;

function TPt.Half: Longint;
begin
  Half := Sum div 2;    { a method calling another method on the same record }
end;

function TPt.Add(const other: TPt): TPt;
begin
  Result.X := X + other.X;
  Result.Y := Y + other.Y;
end;

var
  a, b, c, d: TPt;
begin
  a.Init(3, 4);
  writeln('sum=', a.Sum);
  writeln('half=', a.Half);

  a.Offset(1, 1);       { the receiver must actually change }
  writeln('offset=', a.X, ',', a.Y);

  b.Init(10, 20);
  c := a.Add(b);        { a record-VALUED result }
  writeln('add=', c.X, ',', c.Y);
  writeln('unchanged=', a.X, ',', a.Y, ' ', b.X, ',', b.Y);

  { record CONSTRUCTOR: invoked on the TYPE, materialises a temp, yields it by VALUE.
    It must NOT go through the class Create path — that lowers to GetMem and would
    heap-allocate a record, handing back a pointer where a value belongs. }
  d := TPt.Create(3, 4);
  writeln('ctor=', d.X, ',', d.Y, ' sum=', d.Sum);
  d := MakeAt(5);
  writeln('ctor-via-fn=', d.X, ',', d.Y);

  { class operators. NOTE the operands are VARIABLES: operator dispatch does not yet see a
    record-valued CALL result (`TPt.Create(1,2) + TPt.Create(3,4)` fails to find the
    overload) — filed, not bodged. }
  b := TPt.Create(1, 2);
  c := TPt.Create(10, 20);
  d := b + c;
  writeln('op-plus=', d.X, ',', d.Y);
  b := TPt.Create(11, 22);
  writeln('op-eq=', d = b);
  b := TPt.Create(0, 0);
  writeln('op-neq=', d = b);
end.
