program test_index_through_record_pointer_cast;
{ Indexing an ARRAY or STRING field reached through a record-POINTER CAST.

  The cast chain's `[` arm resolved the element kind for a pointer-to-array
  base and for a scalar alias, and then CLOBBERED tk with tyUnknown for every
  other base -- including the common one, an array FIELD, whose element kind
  the field builder had already put in tk. So `PR(raw)^.m[3]` printed the
  double's BIT PATTERN as an integer with the `:0:2` spec silently ignored, and
  `PR(raw)^.s[2]` printed the string's bytes as an integer, while the identical
  `r.m[3]` / `pv^.m[3]` / `r.s[2]` were right. Wrong value, exit 0, one of three
  spellings of one expression. Pre-dates the 2026-08-27 pin.
  bug-a-an-array-field-indexed-through-a-record-pointer-cast-loses-its-element-type

  The ND rows also pin the comma subscript in EXPRESSION position, which was a
  hard parse error through a cast while the identical STORE compiled:
  bug-a-a-comma-indexed-multi-dim-subscript-is-not-parsed-through-a-cast-or-call-result }
type
  TInner = record v: Integer; end;
  TMD = array[0..1, 0..1] of Double;
  TR = record
    m: array[0..3] of Double;
    s: AnsiString;
    ir: array[0..1] of TInner;
    md: TMD;
  end;
  PR = ^TR;
var
  r: TR;
  pv: PR;
  raw: Pointer;
  i: Integer;
begin
  raw := @r;
  pv := @r;
  for i := 0 to 3 do r.m[i] := (i + 1) * 1.5;
  r.s := 'hello';
  r.ir[1].v := 42;
  for i := 0 to 3 do PR(raw)^.md[i div 2, i mod 2] := (i + 1) * 1.5;

  WriteLn(r.m[3]:0:2);           { 6.00 — the control: no cast }
  WriteLn(pv^.m[3]:0:2);         { 6.00 — a pointer VARIABLE, also a control }
  WriteLn(PR(raw)^.m[3]:0:2);    { 6.00 — was 4618441417868443648 }
  WriteLn(PR(raw)^.md[1][1]:0:2);{ 6.00 — the CHAINED spelling of the same N-D subscript }
  WriteLn(r.s[2]);               { e }
  WriteLn(PR(raw)^.s[2]);        { e — was 1869376613, the bytes of "ello" }
  WriteLn(PR(raw)^.ir[1].v);     { 42 — an array of RECORDS keeps recName }
  WriteLn(r.md[1, 1]:0:2);       { 6.00 }
  WriteLn(PR(raw)^.md[1, 1]:0:2);{ 6.00 — comma subscript in READ position }
  WriteLn(PR(raw)^.md[0, 1]:0:2);{ 3.00 }
end.
