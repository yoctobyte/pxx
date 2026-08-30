program TestEmitObj;
{ Regression source for the relocatable ELF32 object writer (--emit-obj /
  .o output, feature-elf-rel-writer). Exercises every relocation class the
  writer emits: data refs (string literal -> .rela.text vs .data), BSS
  globals (-> .rela.text vs .bss) and an external import (undefined symbol,
  call through a relocated literal slot). Checked with readelf by the
  test-emit-obj Makefile target; not meant to run on the host. }

procedure ext_notify(v: Integer); external;

{ bug-a-emit-obj-ignores-external-name: `name 'sym'` sets the LINK symbol, not
  the Pascal identifier. The object must ask the linker for
  `ext_aliased_link` and must NEVER mention `ext_alias_decl`. The Makefile
  rule asserts BOTH directions on purpose: the pre-fix object compiled
  cleanly and merely carried the wrong name, so a presence-only check of the
  alias is satisfied by an object that is still wrong. }
procedure ext_alias_decl(v: Integer); cdecl; external name 'ext_aliased_link';

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
  ext_alias_decl(g);
  write('done');
end.
