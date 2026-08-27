{ Indexing the RESULT of the dynamic-array `Copy` intrinsic: `Copy(a, 1, 2)[0]`.

  A dyn-array value is a bare heap handle with no address, so AN_INDEX has no
  base to work from. The answer is the hidden dyn-array temp
  IndexDynArrayValue already builds for an array-returning CALL — the Copy arm
  used to Exit straight past the postfix chain, so the trailing `[` reached the
  statement parser as a stray token and reported `unexpected token` at the wrong
  place (dynarray-copy-and-alias in fpc_diff_probe).

  Rows:

    a  the probe's own shape — aliasing vs Copy, then Length(Copy(...)) beside
       Copy(...)[i], which is what caught it: the first worked and the second
       did not
    b  a RECORD element, so the `.field` tail after the index runs
    c  a STRING element (managed), through the same temp
    d  the whole-array shorthand `Copy(a)` indexed directly
    e  the temp does not leak: 200k indexed copies in a loop (RSS measured flat
       at 392kB when this landed; the row here just pins the value)

  Oracled against FPC 3.2.2 -Mobjfpc. }
program test_dynarray_copy_result_indexed;

type
  TP = record x, y: Integer; end;

var
  a, b, c: array of Integer;
  r: array of TP;
  s: array of string;
  i, acc: Integer;

begin
  SetLength(a, 3); a[0] := 1; a[1] := 2; a[2] := 3;
  b := a;                       { alias: same buffer }
  c := Copy(a, 0, 3);           { a real copy }
  b[0] := 99;
  WriteLn('a ', a[0], '|', b[0], '|', c[0]);
  WriteLn('a2 ', Length(Copy(a, 1, 10)), '|', Copy(a, 1, 2)[0]);

  SetLength(r, 3);
  for i := 0 to 2 do begin r[i].x := i; r[i].y := i * 10; end;
  WriteLn('b ', Copy(r, 1, 2)[0].y);

  SetLength(s, 3); s[0] := 'p'; s[1] := 'q'; s[2] := 'r';
  WriteLn('c ', Copy(s, 1, 2)[1]);

  WriteLn('d ', Copy(a)[2]);

  acc := 0;
  for i := 1 to 200000 do
    acc := acc + Copy(a, 1, 2)[0];
  WriteLn('e ', acc);
end.
