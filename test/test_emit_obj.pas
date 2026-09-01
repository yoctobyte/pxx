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

  `g` is DELIBERATELY read here, and what it pins CHANGED on 2026-09-01. It used
  to say: a foreign program does NOT run the Pascal main body, so g is 0 and
  emit_obj_addup(9) is 45. It now says the opposite -- the body runs from
  .init_array, so g is 54 and emit_obj_addup(9) is 99, and stdout carries the
  body's own `done` ahead of the host's line.

  THE OLD COMMENT WAS DESCRIBING A DEFECT, NOT A DESIGN. It was written in
  41045d7b4, the commit that introduced this object writer, at a time when
  nothing ran an object's initialisers because the mechanism did not exist. That
  made "the body does not run" a true statement about the output and a false one
  about the intent: --shared already ran unit init AND the program body (the
  test-shared row says so in its own name), so the two library-shaped outputs
  disagreed about the same source construct, and only one of them had a reason.

  The tripwire itself was right and did its job. It said the test "would still
  pass if initialisation SILENTLY started running, but the VALUE says which
  world we are in" -- a guard against unnoticed drift, not a prohibition. It
  fired, the change was made deliberately and argued in a decision ticket, and
  this comment is the other half of that: a tripwire that is retired quietly is
  worse than no tripwire at all.

  So the VALUE still says which world we are in. It just names the other one.
  decide-a-should-a-pascal-program-compiled-to-an-object-run-its-main-body-when-a-foreign-program-loads-it
  feature-a-a-general-x86-64-relocatable-object-writer }
function emit_obj_addup(n: Integer): Integer; cdecl;
begin
  Result := AddUp(n) + g;
end;

function emit_obj_tag: PChar; cdecl;
begin
  Result := PChar('pxx-emit-obj');
end;

{ @proc, and it is here because its ABSENCE hid a bug. The relocation rows of
  test-emit-obj assert that .text carries no absolute relocation; before this
  routine existed they asserted that over a program with no `@proc` site, and
  IR_PROCADDR was still emitting `mov rax, imm64` -- an R_X86_64_64 against
  .text, which ld accepts into a PIE only by creating DT_TEXTREL and which
  `-Wl,-z,text` refuses. The census said zero because the population could not
  contain it.

  AddUp is deliberately the target: it is a LOCAL symbol, so the relocation is
  against .text itself rather than an exported name. Returning the pointer,
  rather than calling through it, keeps the value observable from C without
  the object needing to run any Pascal initialisation. }
function emit_obj_cbaddr: Pointer; cdecl;
type
  TAddUp = function(n: Integer): Integer;
var
  f: TAddUp;
begin
  f := @AddUp;
  Result := Pointer(@f);
  Result := Pointer(f);
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
