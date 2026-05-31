program test_getmem_proc;
{ Two-argument procedure form GetMem(dest, size) must allocate and store the
  pointer into dest. Covers a plain Pointer, a typed pointer (then indexed),
  and a record-field destination. The function form p := GetMem(size) must
  keep working too. }
type
  PBuf = ^Byte;
  TRec = record buf: PBuf; end;
var
  p: Pointer;
  pb: PBuf;
  r: TRec;
begin
  GetMem(p, 16);
  if p = nil then writeln(0) else writeln(1);

  GetMem(pb, 4);
  pb[0] := 65;
  pb[1] := 66;
  writeln(pb[0]);
  writeln(pb[1]);

  GetMem(r.buf, 4);
  r.buf[0] := 90;
  writeln(r.buf[0]);

  p := GetMem(8);
  if p = nil then writeln(0) else writeln(1);
end.
