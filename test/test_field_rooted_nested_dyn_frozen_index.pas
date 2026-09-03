program test_field_rooted_nested_dyn_frozen_index;
{ A record FIELD of type `array of array of string[N]`: the second subscript
  must be an ELEMENT index into the inner array, not a CHARACTER index into a
  frozen string. It resolved as a character index, so the whole shape was
  uncompilable -- `cannot assign ShortString to Char` -- in BOTH modes and on
  every target, while the identical declaration as a plain VARIABLE worked.

  Cause: two dyn-depth walkers, and the parser-side one had no AN_FIELD arm.
  IsNodeArray asked it, got 0 for `r.matrix`, and the selector chain took the
  index-a-STRING branch. The twins are now one function.
  bug-a-a-field-rooted-array-of-array-of-string-n-indexes-as-a-char

  ONE element per row on purpose. A field-rooted row with SEVERAL frozen
  elements is allocated with a pointer-wide stride and the elements overlap --
  a SEPARATE defect that this shape could not reach before, because it did not
  compile: bug-a-a-frozen-dynamic-array-field-records-a-junk-element-capacity.
  Asserting a multi-element row here would wire a known-red row; asserting the
  VAR spelling beside the FIELD one is what keeps this honest, because the two
  must agree and the variable arm is the one that was always right. }
type
  TS10 = string[10];
  TR = record matrix: array of array of TS10; end;
  TRA = record m: array of array of AnsiString; end;
  TRI = record m: array of array of Integer; end;
var
  r: TR; ra: TRA; ri: TRI;
  v: array of array of TS10;
begin
  SetLength(v, 2); SetLength(v[0], 1); SetLength(v[1], 1);
  v[0][0] := 'var0'; v[1][0] := 'var1';
  WriteLn('VAR   <', v[0][0], '><', v[1][0], '>');

  SetLength(r.matrix, 2); SetLength(r.matrix[0], 1); SetLength(r.matrix[1], 1);
  r.matrix[0][0] := 'fld0'; r.matrix[1][0] := 'fld1';
  WriteLn('FIELD <', r.matrix[0][0], '><', r.matrix[1][0], '>');
  WriteLn('LEN   ', Length(r.matrix), ' ', Length(r.matrix[0]));

  { the same shape with a MANAGED element and with a non-string element: both
    were refused by the same wrong answer, the AnsiString one wearing the same
    "cannot assign ShortString to Char" face. }
  SetLength(ra.m, 1); SetLength(ra.m[0], 2);
  ra.m[0][0] := 'ansi0'; ra.m[0][1] := 'ansi1';
  WriteLn('ANSI  <', ra.m[0][0], '><', ra.m[0][1], '>');
  SetLength(ri.m, 1); SetLength(ri.m[0], 2);
  ri.m[0][0] := 41; ri.m[0][1] := 42;
  WriteLn('INT   ', ri.m[0][0], ' ', ri.m[0][1]);
end.
