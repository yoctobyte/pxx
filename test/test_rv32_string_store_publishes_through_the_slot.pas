program test_rv32_string_store_publishes_through_the_slot;
{ On riscv32 a string assignment calls PXXStrAssign with the slot address:
  the new handle is stored first and the old one released after. Every slot
  kind the store reaches: a frame local, a local past imm12, a var param, an
  out param, a global, and self-assignment at refcount 1 (store-first must
  not free the handle it just stored). Prints the same on x64. }
{$mode objfpc}
{$H+}
var
  g, h: string;
  i: Integer;

function Fresh(const s: string; n: Integer): string;
var k: Integer;
begin
  Result := '';
  for k := 1 to n do Result := Result + s;
end;

function IntToStr(n: Integer): string;
begin
  Str(n, Result);
end;

procedure SetVar(var s: string; const v: string);
begin
  s := v;
  s := s + '!';
  s := s;
end;

procedure SetOut(out s: string; n: Integer);
begin
  s := Fresh('o', n);
end;

procedure FarLocal;
var
  big: array[0..1023] of Integer;
  far1, far2: string;
begin
  big[0] := 1; big[1023] := 2;
  far1 := Fresh('f', 3);
  far2 := far1;
  far1 := far1 + 'x';
  far1 := far1;
  far2 := Fresh('g', 2) + far2;
  writeln('far: ', far1, ' ', far2, ' ', big[0] + big[1023]);
end;

procedure Locals;
var a, b, c: string;
    k: Integer;
begin
  a := Fresh('a', 2);
  b := a;
  a := a + 'z';
  c := b;
  b := '';
  a := a;
  for k := 1 to 5 do
  begin
    c := c + IntToStr(k);
    a := c;
  end;
  writeln('locals: ', a, ' [', b, '] ', c);
  a := 'literal';
  b := a;
  a := 'other';
  writeln('lits: ', a, ' ', b);
end;

var o: string;
begin
  Locals;
  FarLocal;
  g := Fresh('G', 3);
  h := g;
  g := g + 'g';
  g := g;
  writeln('glob: ', g, ' ', h);
  SetVar(g, 'v');
  writeln('var: ', g);
  SetVar(h, h);
  writeln('var self: ', h);
  SetOut(o, 4);
  writeln('out: ', o);
  SetOut(o, 2);
  writeln('out again: ', o);
  for i := 1 to 3 do
  begin
    g := Fresh(g, 2);
    g := Copy(g, 1, 6);
  end;
  writeln('loop: ', g);
  g := '';
  h := '';
  writeln('cleared: [', g, '][', h, ']');
end.
