program test_auto_var;

type
  TPoint = record
    x, y: Integer;
  end;

var
  g_int: auto;
  g_str: auto;
  g_bool: auto;
  g_dbl: auto;
  
procedure TestLocal;
var
  l_int: auto;
  l_str: auto;
  l_bool: auto;
  l_rec: auto;
  p_rec: auto;
  rec: TPoint;
begin
  l_int := 123;
  l_str := 'hello local';
  l_bool := True;
  
  rec.x := 10;
  rec.y := 20;
  l_rec := rec;
  p_rec := @l_rec;

  writeln('Local tests:');
  writeln('l_int = ', l_int);
  writeln('l_str = ', l_str);
  if l_bool then writeln('l_bool is True');
  writeln('l_rec = ', l_rec.x, ', ', l_rec.y);
  writeln('p_rec^ = ', p_rec^.x, ', ', p_rec^.y);
end;

begin
  g_int := 456;
  g_str := 'hello global';
  g_bool := False;
  g_dbl := 3.14;

  writeln('Global tests:');
  writeln('g_int = ', g_int);
  writeln('g_str = ', g_str);
  if not g_bool then writeln('g_bool is False');
  writeln('g_dbl = ', g_dbl:0:2);

  TestLocal;
  writeln('all auto variable tests done!');
end.
