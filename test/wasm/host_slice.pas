{ SPDX-License-Identifier: MPL-2.0 }
{ Phase 6: a wasm module reaching its HOST — stdout, and exit.

  Two independent paths, and keeping them separate is the point.

  1. The IMPORT mechanism, straight from source. `external 'lib' name 'sym'`
     and a wasm import are the same declaration — the module/field pair a wasm
     import needs is exactly what the Pascal form carries — so the WASI surface
     is declarable rather than hardcoded in the backend. RawWrite reaches
     stdout through nothing but that declaration: no RTL, no heap, no data
     relocation, one byte at a time into a fixed buffer.

  2. `writeln`, which goes the long way: IR_WRITE to the RTL's target-neutral
     console helpers, through them to PXXSysWrite, and out through the wasm32
     arm that is itself an `external` declaration of the same kind. Diffed
     against the native build, which shares this source and takes the ordinary
     syscall path instead.

  Path 1 is wrapped in {$ifdef CPU_WASM32} because a native build of an
  external emits a DT_NEEDED for it, and `wasi_snapshot_preview1` is not a
  shared library — the binary builds and then refuses to load. Path 2 is
  target-neutral by construction, which is the whole claim being tested. }
program HostSlice;

{$ifdef CPU_WASM32}
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

{ 'wasm\n', spelled a byte at a time so this depends on the import and on
  nothing else. }
function Emit: Integer;
begin
  Buf[0] := 119;  { w }
  Buf[1] := 97;   { a }
  Buf[2] := 115;  { s }
  Buf[3] := 109;  { m }
  Buf[4] := 10;   { \n }
  Emit := RawWrite(1, @Buf[0], 5);
end;
{$endif}

{ The writeln battery. Every arm of the IR_WRITE lowering that has an RTL
  helper: a literal (a frozen string in Data[], which PXXWriteFrozenW takes
  whole), signed and unsigned integers either side of zero, 64-bit values past
  what an i32 holds, a char, a boolean, and field widths — because the width is
  a separate argument on every helper and a dropped one is invisible in a
  single-value test.

  Called by the native build's main AND exported for the wasm harness, so the
  two runs execute the same source and the diff means something. }
procedure Speak;
var
  i: Integer;
  b: Boolean;
  c: Char;
  w: Int64;
begin
  writeln('hello from wasm');
  writeln(0);
  writeln(42);
  writeln(-7);
  i := 2147483647;  writeln(i);
  i := -2147483648; writeln(i);
  w := 9223372036854775807;  writeln(w);
  w := -9223372036854775807; writeln(w);
  b := True;  writeln(b);
  b := False; writeln(b);
  c := 'Z';   writeln(c);
  writeln(1234:8);
  writeln(-5:4);
  writeln('x':5);
  writeln('end');
end;

begin
  Speak;
end.
