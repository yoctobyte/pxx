program test_reallocmem_grows_and_shrinks_on_every_target;

{ ReallocMem(p, n) keeps the first min(old, new) bytes and stores the new
  pointer back into p. It lowered to special call id -103, which only the
  x86-64 backend implemented, so every other target refused it at build time
  ("builtin/special call not yet supported", builtin id 103), and so did
  lib/rtl/charset.pas. Off x86-64 it is now an ordinary call of the builtin
  unit's PXXRealloc. Covers growing, shrinking, a nil pointer, a record field
  grown one element at a time, and an untyped Pointer. Checked against FPC
  3.2.2. bug-a-reallocmem-builds-only-on-x86-64 }
{$mode objfpc}
type PInt = ^LongInt;
type TBuf = record buf: PInt; n: LongInt; end;
var p, q: PInt; i, bad: LongInt; pp: Pointer;

{ a record FIELD as the target, grown one element at a time }
procedure FieldGrow;
var rec: TBuf; i, bad: LongInt;
begin
  rec.buf := nil; rec.n := 0;
  for i := 1 to 50 do
  begin
    ReallocMem(rec.buf, i * SizeOf(LongInt));
    rec.buf[i - 1] := i; rec.n := i;
  end;
  bad := 0;
  for i := 0 to rec.n - 1 do if rec.buf[i] <> i + 1 then Inc(bad);
  WriteLn('field grow ok ', bad = 0, ' last ', rec.buf[49]);
  FreeMem(rec.buf);
end;

begin
  bad := 0;
  GetMem(p, 4 * SizeOf(LongInt));
  for i := 0 to 3 do p[i] := i * 11;
  ReallocMem(p, 1000 * SizeOf(LongInt));          { grow: first 4 kept }
  for i := 4 to 999 do p[i] := i * 11;
  for i := 0 to 999 do if p[i] <> i * 11 then Inc(bad);
  WriteLn('grow ok ', bad = 0);
  ReallocMem(p, 10 * SizeOf(LongInt));            { shrink: first 10 kept }
  bad := 0;
  for i := 0 to 9 do if p[i] <> i * 11 then Inc(bad);
  WriteLn('shrink ok ', bad = 0);
  q := nil;
  ReallocMem(q, 8 * SizeOf(LongInt));             { nil: acts as GetMem }
  for i := 0 to 7 do q[i] := -i;
  WriteLn('from nil ', q[7]);
  FieldGrow;
  pp := nil;
  ReallocMem(pp, 16);
  WriteLn('untyped ', pp <> nil);
  FreeMem(p); FreeMem(q); FreeMem(pp);
  WriteLn('done');
end.
