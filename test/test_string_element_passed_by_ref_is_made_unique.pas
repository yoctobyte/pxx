program test_string_element_passed_by_ref_is_made_unique;
{ A string element handed to a var/out parameter, or used as a Move/FillChar
  destination, is made unique before the callee writes through it -- as
  `s[i] := c` is. Before: a literal-shared string segfaulted (the write hit
  read-only bytes) and a refcount-2 string edited its alias too. Every row is
  fpc 3.2.2's output. `@s[i]` is not in here: FPC does not make that unique. }
{$mode objfpc}{$H+}
type
  TRec = record s: AnsiString; end;
procedure SetC(var c: char); begin c := 'y' end;
procedure OutC(out c: char); begin c := 'z' end;
procedure ReadC(const c: char); begin Write(c) end;
procedure ViaParam(var s: AnsiString); begin SetC(s[1]) end;
procedure ViaValue(s: AnsiString); begin SetC(s[2]); WriteLn('value ', s) end;
var s, t, u: AnsiString; r: TRec; a: array[0..1] of AnsiString;
    buf: array[0..1] of Char; i: Integer;
begin
  s := 'abc'; SetC(s[2]); WriteLn('lit var ', s);
  s := 'abc'; OutC(s[3]); WriteLn('lit out ', s);
  t := 'de' + 'fg'; u := t; SetC(u[1]); WriteLn('rc2 ', t, ' ', u);
  s := 'ab' + 'cd'; SetC(s[4]); WriteLn('uniq ', s);
  s := 'hello'; buf[0] := 'J'; buf[1] := 'Y'; Move(buf[0], s[1], 2); WriteLn('move ', s);
  t := 'hel' + 'lo'; u := t; Move(buf[0], u[4], 2); WriteLn('move rc2 ', t, ' ', u);
  s := 'hello'; FillChar(s[2], 2, Ord('-')); WriteLn('fill ', s);
  t := 'wor' + 'ld'; u := t; ViaParam(u); WriteLn('var param ', t, ' ', u);
  s := 'lit'; ViaParam(s); WriteLn('var param lit ', s);
  t := 'val' + 'ue'; ViaValue(t); WriteLn('caller ', t);
  r.s := 'rec'; t := r.s; SetC(r.s[3]); WriteLn('field ', t, ' ', r.s);
  a[0] := 'arr'; a[1] := a[0]; SetC(a[1][1]); WriteLn('element ', a[0], ' ', a[1]);
  s := 'con'; t := s; ReadC(t[2]); WriteLn(' const ', s, ' ', t);
  for i := 1 to 3 do begin s := 'loop'; SetC(s[i]); Write(s, ' ') end;
  WriteLn;
end.
