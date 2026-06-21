program test_esp_procaddr;
{ @proc address on the ESP bare riscv32 ET_EXEC image: `@Routine` yields the
  routine's absolute code address (IR_PROCADDR -> PC-relative literal load,
  patched to entry+BodyAddr by the ELF writer). Needed to install a raw ISR in
  mtvec and to hand @isr to esp_intr_alloc. Probe: take two proc addresses, show
  they are distinct, non-zero, and ordered (B emitted after A). Output is exact
  (1/1/1) so it diffs against the x86-64 oracle. }
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}

procedure PutBool(b: Boolean);
begin
  if b then PutC(49) else PutC(48);
  PutC(10);
end;

procedure RoutineA;
begin
  PutC(65);
end;

procedure RoutineB;
begin
  PutC(66);
end;

var
  pa, pb: Pointer;
begin
  pa := @RoutineA;
  pb := @RoutineB;
  PutBool(Integer(pa) <> 0);          { 1: address resolved }
  PutBool(pa <> pb);                  { 1: distinct routines }
  PutBool(Integer(pb) > Integer(pa)); { 1: B emitted after A }
end.
