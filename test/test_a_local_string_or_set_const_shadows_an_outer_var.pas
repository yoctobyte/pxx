{ A routine's own string or set constant shadows a same-named variable of an
  OUTER scope, at every depth, and a variable shadows an outer constant the
  same way. The string-const guard let a variable at ANY depth win, so `A`
  and `B` printed the global integer (1) instead of 'A const' with no
  diagnostic, and the set-const path read the integer `digs` and crashed in
  `'5' in digs`. A one-character const never showed it (a char symbol).
  Expected output is fpc 3.2.2's.
  bug-p-a-local-string-const-does-not-shadow-an-outer-var }
program test_a_local_string_or_set_const_shadows_an_outer_var;
{$mode objfpc}
const G = 'global const';
var outer: Integer;
    digs: Integer;
procedure A;
const outer = 'A const';
  procedure B;
  begin writeln('B ', outer); end;
  procedure C;
  var outer: Integer;
  begin outer := 3; writeln('C ', outer); end;
begin B; C; writeln('A ', outer); end;
procedure D;
var G: Integer;
begin G := 4; writeln('D ', G); end;
procedure E;
var outer: AnsiString;
  procedure F;
  const outer = 'F const';
  begin writeln('F ', outer); end;
begin outer := 'E var'; F; writeln('E ', outer); end;
procedure H;
const digs = ['0'..'9'];
begin writeln('H ', '5' in digs); end;
begin outer := 1; digs := 2; A; D; E; H; writeln('main ', outer, ' ', G); end.
