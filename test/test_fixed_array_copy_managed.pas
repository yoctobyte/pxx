program test_fixed_array_copy_managed;
{ Regression: whole static-array assignment `b := a` where the ELEMENTS are
  managed (AnsiString, or a record with a string field) must copy every element
  and keep the refcounts right. It used to fall off the memcpy path onto the
  scalar store, which copies no array at all: `b := a` produced all-empty
  strings, `a := a` destroyed a[0], and the same array as a record FIELD
  (`y.arr := x.arr`) copied only element 0.
  Also covers `array of string[N]`, whose slot is a length word + N chars —
  TypeSize's default 8 copied only the first element.
  bug-a-static-array-of-managed-whole-assign-loses-data. }
type
  TR = record s: string; n: Integer; end;
  TB = record arr: array[0..2] of string; end;
var
  a, b: array[0..2] of string;
  c, d: array[0..1] of string[8];
  g, h: array[0..1] of TR;
  m, n: array[0..1, 0..1] of string;
  x, y: TB;
begin
  a[0] := 'p'; a[1] := 'q'; a[2] := 'r';
  b := a;
  a[0] := 'CLOBBER';                 { must not disturb b }
  writeln(b[0], b[1], b[2]);         { pqr }

  { self-assignment: retain-before-release keeps every handle alive }
  a[0] := 'p';
  a := a;
  writeln(a[0], a[1], a[2]);         { pqr }

  { destination already holding handles: its old ones must be released, not
    leaked, and the new ones must survive }
  b[0] := 'z'; b[1] := 'z'; b[2] := 'z';
  b := a;
  writeln(b[0], b[1], b[2]);         { pqr }

  c[0] := 'xy'; c[1] := 'zw';
  d := c;
  writeln(d[0], d[1]);               { xyzw }

  g[0].s := 'gs0'; g[0].n := 1; g[1].s := 'gs1'; g[1].n := 2;
  h := g;
  g[1].s := 'CLOBBER';
  writeln(h[0].s, h[1].s, h[1].n);   { gs0gs12 }

  m[0, 0] := 'a'; m[0, 1] := 'b'; m[1, 0] := 'c'; m[1, 1] := 'd';
  n := m;
  writeln(n[0, 0], n[0, 1], n[1, 0], n[1, 1]);   { abcd }

  x.arr[0] := 'f0'; x.arr[1] := 'f1'; x.arr[2] := 'f2';
  y.arr := x.arr;
  x.arr[1] := 'CLOBBER';
  writeln(y.arr[0], y.arr[1], y.arr[2]);         { f0f1f2 }
  writeln('OK');
end.
