program cmt;
{ This comment mentions a {$ifdef CPU32} directive and a {$endif} inline. }
var x: Integer;
begin
  x := 42;       { another {$define FOO} in prose }
  writeln(x);
end.
