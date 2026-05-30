program test_resource;

{ Phase 4: embed a file with the R directive and read it back at runtime via
  FindResource. Asserts length + byte content. }

{$R greeting greeting.dat}

uses resources;

type
  PByte = ^Byte;

var
  data: Pointer;
  len:  Integer;
  i:    Integer;
  p:    PByte;
  s:    string;

begin
  if not FindResource('greeting', data, len) then
  begin
    writeln('not found');
    Halt(1);
  end;
  writeln('len=', len);
  p := data;
  s := '';
  SetLength(s, len);
  for i := 1 to len do
    s[i] := Chr(p[i-1]);
  writeln('data=', s);

  { a missing resource returns False }
  if FindResource('nope', data, len) then
    writeln('missing: FAIL')
  else
    writeln('missing: ok');
end.
