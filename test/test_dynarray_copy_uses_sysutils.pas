{ `Copy(a)` — FPC's whole-array shorthand for a dynamic array — with sysutils in
  scope, so a string `Copy` overload EXISTS.

  That is a different code path from the bare intrinsic, not a variation on it:
  with no `Copy` function in scope ParseFactor claims the call directly, while
  here overload matching runs first, fails, and the dynarray form is recovered at
  the no-overload-match point. Both arms implement dynamic-array Copy, and when
  the one-argument form was added to only one of them the two failed differently
  — "unexpected token (Expected: ,)" without sysutils, "no overload of Copy
  matches these arguments" with it. Hence a test per arm
  (bug-p-copy-single-argument-form-missing-for-dynamic-arrays,
  devdocs/dev/normalise-dont-special-case.md).

  The string Copy must keep working alongside it, which is the reason the
  shorthand is dynarray-only: FPC rejects `Copy(s)` on a string, and so does pxx. }
program test_dynarray_copy_uses_sysutils;

uses sysutils;

var
  a, b: array of Integer;
  s: string;

begin
  SetLength(a, 3);
  a[0] := 1; a[1] := 2; a[2] := 3;

  b := Copy(a);                                 { the shorthand, shadowed arm }
  Writeln(Length(b), ' ', b[0], ' ', b[2]);     { 3 1 3 }

  b[0] := 99;                                   { independent, not an alias }
  Writeln(a[0], ' ', b[0]);                     { 1 99 }

  { the string overload is untouched by any of this }
  s := 'hello';
  Writeln(Copy(s, 2, 3));                       { ell }

  { and the explicit three-argument dynarray form still routes here correctly }
  b := Copy(a, 0, 3);
  b[0] := 4;
  Writeln(Length(b) + 2, ' ', b[0]);            { 5 4 }
end.
