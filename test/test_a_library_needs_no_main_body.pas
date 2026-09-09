{ compat-p-a-library-still-requires-a-begin-end-main-body.

  BYTE-FOR-BYTE test_library_exports.pas WITHOUT its trailing `begin end.`, and
  linked against the SAME host, so the row asserts the thing that matters: not
  that the file parses, but that a library with no statement part produces the
  same working export surface as one with an empty statement part. A parse-only
  assertion would pass on a compiler that dropped the whole file on the floor.

  fpc 3.2.2 accepts this and REFUSES `program p; end.` — measured, not assumed
  from symmetry, which is why the Makefile row beside this one keeps the program
  form as a negative control. A library with nothing to initialise is the common
  shape: the export surface is the point of the file. }
library test_a_library_needs_no_main_body;

function PxxLibAdd(a, b: Integer): Integer; cdecl;
begin
  PxxLibAdd := a + b;
end;

function PxxLibMul(a, b: Integer): Integer; cdecl;
begin
  PxxLibMul := a * b;
end;

exports PxxLibNegate;

{ `Hidden` is here to be ABSENT, exactly as in the sibling file: not exported,
  not `cdecl`, so it must stay a LOCAL symbol. Without it the row would pass on
  a compiler that exported everything. }
function Hidden(a: Integer): Integer;
begin
  Hidden := a - 1;
end;

function PxxLibNegate(a: Integer): Integer; cdecl;
begin
  PxxLibNegate := -a - Hidden(1);
end;

exports PxxLibAdd, PxxLibMul;
end.
