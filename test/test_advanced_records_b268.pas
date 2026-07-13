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
    procedure Init(ax, ay: Longint);
    procedure Offset(dx, dy: Longint);
    function Sum: Longint;
    function Add(const other: TPt): TPt;
  private
    function Half: Longint;
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
  a, b, c: TPt;
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
end.
