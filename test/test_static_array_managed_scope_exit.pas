program test_static_array_managed_scope_exit;
{ Regression: a STATIC array local whose elements are managed must release EVERY
  element at scope exit.

  An array's TypeKind IS its element kind, so `array[0..N] of string` fell into
  the SCALAR AnsiString cleanup arm and released element 0 only — the other N
  leaked, silently and linearly. Measured before the fix, 400k calls:
  1 element flat, 3 elements 24.9 MB, 6 elements 62.5 MB — exactly (N-1)
  leaking. An array of managed RECORDS leaked all of them, because
  SymNeedsManagedCleanup's record arm excluded arrays and so no cleanup was
  emitted at all.

  This test cannot assert RSS portably, so it asserts what a correct release
  implies and what a WRONG one would break: the values must survive intact
  (a premature or double release shows up as corruption or a crash), across
  repeated calls so a stale-handle reuse has a chance to surface.
  The leak itself is measured in the ticket.
  bug-a-local-static-array-of-string-never-released-at-scope-exit }
type TR = record s: string; n: Integer; end;

function Strings(pass: Integer): Integer;
var a: array[0..2] of string; i: Integer;
begin
  for i := 0 to 2 do a[i] := 'v' + Chr(48 + pass) + Chr(48 + i);
  Strings := 0;
  for i := 0 to 2 do
    if a[i] <> 'v' + Chr(48 + pass) + Chr(48 + i) then Strings := Strings + 1;
end;

function Records(pass: Integer): Integer;
var a: array[0..2] of TR; i: Integer;
begin
  for i := 0 to 2 do begin a[i].s := 'r' + Chr(48 + i); a[i].n := pass; end;
  Records := 0;
  for i := 0 to 2 do
    if (a[i].s <> 'r' + Chr(48 + i)) or (a[i].n <> pass) then Records := Records + 1;
end;

function TwoD(pass: Integer): Integer;
var a: array[0..1, 0..1] of string; i, j: Integer;
begin
  for i := 0 to 1 do for j := 0 to 1 do a[i, j] := Chr(65 + i) + Chr(48 + j);
  TwoD := 0;
  for i := 0 to 1 do for j := 0 to 1 do
    if a[i, j] <> Chr(65 + i) + Chr(48 + j) then TwoD := TwoD + 1;
end;

var k, bad: Integer;
begin
  bad := 0;
  for k := 0 to 199 do
  begin
    bad := bad + Strings(k mod 10);
    bad := bad + Records(k mod 10);
    bad := bad + TwoD(k);
  end;
  writeln(bad);
  writeln('OK');
end.
