program procs;

{ i386 cross-target slice 3: procedures and 32-bit frames. Internal i386
  convention: caller pushes args left-to-right (leftmost deepest), callee
  spills [ebp+8+(n-1-i)*4] into frame slots, caller cleans the arg area.
  Covers functions, recursion, a procedure with a local, nested calls, and
  Exit. Output must be identical to the x86-64 build. }

var g: Integer;

function Add3(a, b, c: Integer): Integer;
begin
  Add3 := a + b * c;
end;

function Fact(n: Integer): Integer;
begin
  if n <= 1 then Fact := 1
  else Fact := n * Fact(n - 1);
end;

function Pick(n: Integer): Integer;
begin
  if n > 5 then
  begin
    Pick := 99;
    Exit;
  end;
  Pick := n;
end;

procedure Shout(n: Integer);
var k: Integer;
begin
  k := n * 2;
  writeln(k);
end;

begin
  g := Add3(1, 2, 3);
  writeln(g);
  writeln(Fact(6));
  Shout(21);
  writeln(Add3(Fact(4), 10, 2));
  writeln(Pick(10));
  writeln(Pick(3));
end.
