program lib_variants_surface;
{ The `variants` unit's FPC surface, over pxx's own 16-byte tagged Variant.

  Four entry points arrived late and each was found by a program that could not
  be written without it: VarClear (bug-a-varclear-is-undefined -- the empty-slot
  row of a Variant differential could not be produced from Pascal at all), and
  VarToStr / VarToStrDef / VarIsClear (bug-b-vartostr-is-missing-from-variants,
  found writing the FPC oracle for an `out Variant` test).

  Every row below is byte-identical to fpc 3.2.2 on the same source, diffed
  rather than reasoned about.

  The ARC loop at the end is the row that matters most: VarClear must release a
  REFERENCE, not the object. `keep` owns the same payload, so a missing release
  leaks and a double release frees `keep` under this program and the Copy reads
  freed memory. }
{$mode objfpc}{$H+}
uses variants, SysUtils;
var v: Variant; keep: AnsiString; i, bad: Integer;
begin
  v := 'hey';   VarClear(v);   WriteLn('clear    [', VarToStr(v), '] empty=', VarIsEmpty(v));
  v := 42;      WriteLn('int      [', VarToStr(v), ']');
  v := True;    WriteLn('bool     [', VarToStr(v), ']');
  v := 'text';  WriteLn('str      [', VarToStr(v), ']');
  { FPC's documented special case, and the reason VarToStr exists at all: a Null
    yields '' where the plain `s := v` cast raises EVariantTypeCastError. }
  v := Null;    WriteLn('null     [', VarToStr(v), ']');
  v := 7;       WriteLn('def-set  [', VarToStrDef(v, 'D'), ']');
  v := Null;    WriteLn('def-null [', VarToStrDef(v, 'D'), ']');
  v := 'x';     WriteLn('isclear0 ', VarIsClear(v));
  VarClear(v);  WriteLn('isclear1 ', VarIsClear(v));

  bad := 0;
  for i := 1 to 2000 do
  begin
    keep := 'payload-' + IntToStr(i);
    v := keep;
    VarClear(v);
    if keep = '' then Inc(bad);
  end;
  WriteLn('survive  [', Copy(keep, 1, 8), '] bad=', bad);
end.
