program test_lazy_var;

procedure TestBasic;
begin
  writeln('Basic tests:');
  var a := 123;
  var b := 'hello inline';
  var c := 3.14;
  var d := True;
  
  writeln('a = ', a);
  writeln('b = ', b);
  writeln('c = ', c:0:2);
  if d then writeln('d is True');
end;

procedure TestScoping;
begin
  writeln('Scoping tests:');
  var x := 10;
  writeln('outer x = ', x);
  begin
    var x := 20;
    var y := 30;
    writeln('inner x = ', x);
    writeln('inner y = ', y);
  end;
  writeln('outer x after block = ', x);
end;

procedure TestMultiple;
begin
  writeln('Multiple declarations:');
  var x, y: Integer;
  x := 42;
  y := 24;
  writeln('x = ', x, ', y = ', y);
end;

begin
  TestBasic;
  TestScoping;
  TestMultiple;
  writeln('all lazy variable tests done!');
end.
