program test_esp_isr_register;
{ ESP-IDF ISR registration path: an `interrupt;` (or `iram;`) handler whose
  address is handed to esp_intr_alloc via @Handler. On the --emit-obj relocatable
  object, @Handler emits an absolute (R_RISCV_32) relocation against the handler's
  own symbol so the IDF linker fills the final address. Structural probe — compile
  with --emit-obj and `readelf -r` should show the reloc against MyIsr. (Bare
  ET_EXEC patches @proc directly; this is the .o / IDF half.) }
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure esp_intr_alloc(source: Integer; flags: Integer; handler: Pointer; arg: Pointer; ret: Pointer); external;
{$endif}

var
  hits: Integer;

procedure MyIsr(arg: Pointer); iram;
begin
  hits := hits + 1;
{$ifdef PXX_ESP}
  esp_rom_printf('isr %d'#10, hits);
{$endif}
end;

var
  h: Pointer;
begin
  hits := 0;
  h := @MyIsr;
{$ifdef PXX_ESP}
  esp_intr_alloc(0, 0, h, nil, nil);   { register the Pascal ISR with the IDF }
{$endif}
end.
