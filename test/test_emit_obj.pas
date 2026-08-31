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

{ The x86-64 general object writer's export surface is the C-convention set
  (ProcCdecl), so these two are what make the x86-64 rows of test-emit-obj
  assert an object a linker can consume rather than only a refusal. Between
  them they carry all three x86-64 relocation kinds an exported routine can
  reach: a .bss global (R_X86_64_32S vs .bss), a string literal (R_X86_64_64
  vs .data) and an intra-object call.

  `g` is DELIBERATELY read here. A foreign program that links this object does
  NOT run the Pascal main body, so g is 0 at every call from C and
  emit_obj_addup(9) is 45, not 45+9. That is the property being pinned: the
  test would still pass if initialisation silently started running, but the
  VALUE says which world we are in.
  feature-a-a-general-x86-64-relocatable-object-writer }
function emit_obj_addup(n: Integer): Integer; cdecl;
begin
  Result := AddUp(n) + g;
end;

function emit_obj_tag: PChar; cdecl;
begin
  Result := PChar('pxx-emit-obj');
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
