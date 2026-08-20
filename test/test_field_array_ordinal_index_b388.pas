program test_field_array_ordinal_index_b388;
{ A whole ordinal TYPE as a field array's index range — `array[TTypeKind] of X`
  in a class or record FIELD, the shape rtl-generics' comparer tables are built
  from. A var section had accepted it since the `array[Byte]` work; the field
  paths parsed their bounds with a bare ConstEval, which can only see `lo..hi`,
  so the identical declaration answered `not a constant` one nesting level in.
  Both now go through ParseArrayDimBounds -- and so do the NAMED array-type
  section (`TA = array[TKind] of X`), which was another copy of the same
  bare-ConstEval bound parser, found by widening this test. The in-statement
  `var` decl (ParseLazyVarDeclAST) was a further copy and is fixed too, but
  cannot be tested here: FPC 3.2.2 has no inline var, so it would cost the
  oracle. Values checked against fpc 3.2.2.
  feature-pascal-corpus-generics (rung 3, wall 18). }
{$mode objfpc}{$H+}
type
  TKind = (kRed, kGreen, kBlue);

  TRec = record
    E: array[TKind] of Integer;
    B: array[Byte] of Byte;
  end;

  { A NAMED array type with an ordinal index: its own copy of the bound parser
    lives in the type section, and it answered `not a constant` too. }
  TNamed = array[TKind] of Integer;
  TNamedC = array[Char] of Byte;

  TCls = class
    E: array[TKind] of Integer;
    C: array[Char] of Byte;
    L: array[Boolean] of Integer;
    N: array[TKind, 0..1] of Integer;
    A: TNamed;             { the named type, as an ordinary field }
  end;

var
  r: TRec;
  c: TCls;
  k: TKind;
  nv: TNamed;
  nc: TNamedC;
  ok: Boolean;
begin
  ok := True;

  for k := kRed to kBlue do r.E[k] := Ord(k) * 10;
  r.B[0] := 1; r.B[255] := 2;
  if (r.E[kRed] <> 0) or (r.E[kGreen] <> 10) or (r.E[kBlue] <> 20) then ok := False;
  if (r.B[0] <> 1) or (r.B[255] <> 2) then ok := False;

  { The named types, as plain vars and as a field. }
  for k := kRed to kBlue do nv[k] := Ord(k) * 3;
  nc['Z'] := 90;
  if (nv[kRed] <> 0) or (nv[kBlue] <> 6) or (nc['Z'] <> 90) then ok := False;

  c := TCls.Create;
  for k := kRed to kBlue do c.E[k] := Ord(k) + 100;
  c.C['A'] := 65; c.C[#0] := 7;
  c.L[False] := 3; c.L[True] := 4;
  c.N[kRed, 0] := 1; c.N[kBlue, 1] := 6;
  if (c.E[kRed] <> 100) or (c.E[kBlue] <> 102) then ok := False;
  if (c.C['A'] <> 65) or (c.C[#0] <> 7) then ok := False;
  if (c.L[False] <> 3) or (c.L[True] <> 4) then ok := False;
  if (c.N[kRed, 0] <> 1) or (c.N[kBlue, 1] <> 6) then ok := False;
  c.A[kBlue] := 55;
  if c.A[kBlue] <> 55 then ok := False;

  if not ok then
  begin
    Writeln('test_field_array_ordinal_index_b388: FAIL');
    Halt(1);
  end;
  Writeln('test_field_array_ordinal_index_b388: OK');
end.
