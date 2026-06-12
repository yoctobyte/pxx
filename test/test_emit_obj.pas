program TestEmitObj;
{ Regression source for the relocatable ELF32 object writer (--emit-obj /
  .o output, feature-elf-rel-writer). Exercises every relocation class the
  writer emits: data refs (string literal -> .rela.text vs .data), BSS
  globals (-> .rela.text vs .bss) and an external import (undefined symbol,
  call through a relocated literal slot). Checked with readelf by the
  test-emit-obj Makefile target; not meant to run on the host. }

procedure ext_notify(v: Integer); external;

var
  g: Integer;
  i: Integer;

function AddUp(n: Integer): Integer;
var k, acc: Integer;
begin
  acc := 0;
  for k := 1 to n do acc := acc + k;
  Result := acc;
end;

begin
  g := 0;
  for i := 1 to 9 do
    g := g + 1;
  g := AddUp(9) + g;
  ext_notify(g);
  write('done');
end.
