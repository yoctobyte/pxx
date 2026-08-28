{ SPDX-License-Identifier: MPL-2.0 }
{ Phase 6, first milestone: a wasm module that reaches its HOST.

  Two independent things are under test here and they must not be confused.
  
  1. The IMPORT mechanism. `external 'lib' name 'sym'` and a wasm import are
     the same declaration — the module/field pair a wasm import needs is
     exactly what the Pascal form carries — so the WASI surface is declarable
     from source rather than hardcoded in the backend. RawWrite below reaches
     stdout through nothing but that declaration.
  
  2. `writeln` itself, which lowers to the RTL's target-neutral console
     helpers and through them to PXXSysWrite — an ifdef chain over
     __pxxrawsyscall with an arm per target and NO wasm32 arm, so it returns 0
     having written nothing. builtinheap.pas is a shared file; the arm is
     bug-a-pxxsyswrite-has-no-wasm32-arm.
  
  So (1) prints and (2) is SILENT, and the harness asserts both — the silence
  as loudly as the output, because the day `writeln` starts working is the day
  this file's claim about it stops being true. }
program WriteSlice;

function fd_write(fd: Integer; iovs: Pointer; iovsLen: Integer;
                  nwritten: Pointer): Integer;
  external 'wasi_snapshot_preview1' name 'fd_write';

var
  IOV: array[0..1] of Integer;   { one iovec: [ptr, len] }
  NW : Integer;
  Buf: array[0..15] of Byte;

{ write(fd, p, n) through WASI. Returns the byte count, or -1 on a WASI errno. }
function RawWrite(fd: Integer; p: Pointer; n: Integer): Integer;
begin
  IOV[0] := Integer(p);
  IOV[1] := n;
  NW := 0;
  if fd_write(fd, @IOV[0], 1, @NW) = 0 then RawWrite := NW
  else RawWrite := -1;
end;

{ 'wasm\n' — spelled a byte at a time so the test depends on the import and on
  nothing else: no string helper, no heap, no data relocation. }
function Emit: Integer;
begin
  Buf[0] := 119;  { w }
  Buf[1] := 97;   { a }
  Buf[2] := 115;  { s }
  Buf[3] := 109;  { m }
  Buf[4] := 10;   { \n }
  Emit := RawWrite(1, @Buf[0], 5);
end;

{ writeln of an integer. Lowers through PXXWriteDecW + PXXWriteNL and reaches
  PXXSysWrite, which on this target writes nothing. Exported so the harness can
  call it and assert the silence. }
procedure TryWriteln;
begin
  writeln(42);
end;

begin
end.
