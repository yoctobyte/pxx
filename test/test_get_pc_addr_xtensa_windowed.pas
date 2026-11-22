{ get_pc_addr -- the same node as C's __builtin_return_address(0), and in
  pxx the CURRENT FUNCTION'S RETURN ADDRESS (FPC 3.2.2 answers the PC inside
  the caller instead: compat-p-get-pc-addr-is-the-return-address-not-the-pc)
  -- on xtensa's windowed ABI, checked against pxx x86-64. pxx refused it on
  xtensa (no frame chain); Rainyday's mm/kmalloc.c tags poisoned blocks with
  its caller, so the ESP32-S3 kernel stopped compiling.
  feature-xtensa-builtin-return-address }
program test_get_pc_addr_xtensa_windowed;
var a, b, c, keep: Pointer;

function Where: Pointer;
begin
  Where := get_pc_addr;
end;

function AfterCalls(n: Integer): Pointer;
var i: Integer;
begin
  for i := 1 to n do Write('');
  keep := get_pc_addr;
  AfterCalls := get_pc_addr;
end;

begin
  a := Where;
  b := Where;
  c := AfterCalls(3);
  WriteLn('distinct ', a <> b, ' increasing ', PtrUInt(b) > PtrUInt(a));
  WriteLn('stable ', c = keep, ' near ', (PtrUInt(b) - PtrUInt(a)) < 256);
  WriteLn('top bits kept ', (PtrUInt(a) shr 30) = (PtrUInt(@Where) shr 30));
end.
