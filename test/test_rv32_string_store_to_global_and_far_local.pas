program test_rv32_string_store_to_global_and_far_local;
{ riscv32 stores a managed string into a global, or into a local whose frame
  offset is past the 12-bit immediate, the way it already stored into a near
  local: slot address into t0, old handle into a1, store the new one, then
  release the old. New holds its own +1 first, so g := g at refcount 1 must
  survive. And a copy of a plain local (s := t) re-reads t after the IncRef
  instead of keeping the handle on the stack across the call. Values only, so
  x86-64 is the oracle; Churn runs every shape 500 times under the census. }
{$mode objfpc}
uses SysUtils;
var
  g, h: AnsiString;
  hits: LongInt;

procedure Far(k: LongInt);
var pad: array[0..700] of LongInt; s, t: AnsiString; i: LongInt;
begin
  for i := 0 to High(pad) do pad[i] := i;
  s := 'f' + IntToStr(k);              { s and t sit past imm12 }
  t := s;
  s := s;
  t := t + '!';
  s := t;
  g := s;
  if (s = t) and (g = s) and (pad[700] = 700) then Inc(hits);
end;

procedure Near(k: LongInt);
var a, b: AnsiString;
begin
  a := 'n' + IntToStr(k);
  b := a;                              { copy of a plain local }
  a := b;
  b := b;
  g := a;
  h := g;                              { global from global }
  g := g;                              { two refs }
  h := '';
  g := g;                              { refcount: a, b, g }
  a := ''; b := '';
  g := g;                              { refcount 1 }
  h := 'h' + g;
  if (g = 'n' + IntToStr(k)) and (h = 'hn' + IntToStr(k)) then Inc(hits);
end;

procedure Churn;
var k: LongInt;
begin
  for k := 1 to 500 do
  begin
    Near(k);
    Far(k);
    g := 'only' + IntToStr(k);         { fresh, refcount 1 }
    g := g;
    h := g;
    g := h;
    h := '';
  end;
  writeln(hits, ' ', g, ' ', h, '.');
end;

begin
  hits := 0;
  Near(7); writeln(g, ' ', h);
  Far(9); writeln(g);
  Churn;
  g := ''; h := '';
  writeln('done');
end.
