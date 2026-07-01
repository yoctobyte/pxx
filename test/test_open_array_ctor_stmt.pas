program test_open_array_ctor_stmt;

function f(const a: array of integer): integer;
begin
  f := Length(a);
end;

procedure p(const a: array of integer);
var i: integer;
begin
  for i := 0 to High(a) do
    write(a[i], ' ');
  writeln;
end;

{ bug-array-ctor-statement-arg-after-dynarray-record-param: a preceding const
  record param whose type has a dynamic-array field used to hit a different
  (misleading) "too many array constant elements" error instead of the
  generic by-reference-argument-must-be-a-variable bug above -- confirmed
  fixed as a side effect of the same statement-arg fix, re-verified here. }
type TBuf = record Bytes: array of Byte; Len: Integer; end;
procedure Check(const name: AnsiString; const buf: TBuf; const a: array of Byte);
begin
  writeln(name, ' ', Length(a));
end;

var r: integer; b: TBuf;
begin
  r := f([1, 2, 3]);   { expression context, already worked }
  writeln(r);
  f([4, 5]);           { statement context, result discarded }
  p([1, 2, 3]);        { procedure, statement-only }
  p([]);               { empty ctor, statement context }
  Check('hi', b, [1, 2, 3, 4, 5]);
end.
