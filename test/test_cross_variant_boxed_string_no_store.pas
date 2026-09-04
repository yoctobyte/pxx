{ BOXING A STRING INTO A VARIANT IN A BODY THAT HAS NO MANAGED-STRING STORE.

  wasm32 keeps four per-body scratch locals for managed strings, allocated on
  demand and reset to -1 at each body's start. `msval` -- the one that holds a
  string value while it is being materialised -- was allocated by the managed
  STORE path only, and WasmVariantPayload calls the same materialiser without
  going through a store. So a body that boxes a string and never assigns one
  emitted `local.set -1`.

  A negative index is not an error in an LEB128 writer: `x shr 7` on -1 walks
  ten continuation bytes, so the module was WRITTEN. The compile printed `ok:`,
  the coverage report recorded no gap, and the invalid module was only rejected
  at load. Every check that stops at "did it build" passed.
  bug-a-wasm32-emitted-a-negative-local-index-and-the-module-was-written-anyway

  WHY THE EXISTING VARIANT ROWS DID NOT CATCH IT, and it is the point of this
  file. test_cross_variant boxes STRING LITERALS -- `v := 'hello'` -- and a
  literal is materialised through the string POOL, not through msval. The arms
  that use msval are the ANSISTRING one and the FROZEN one, and reaching either
  needs a string VARIABLE. Boxing a variable at top level does not do it
  either: `s := 'x'; v := s;` allocates msval on the first statement. The defect
  needs a body whose box is not preceded by a store, which is what every
  procedure here is -- the parameter carries the string in.

  MEASURED, not argued: the pre-fix compiler was rebuilt and all four existing
  wasm32 variant rows -- test_cross_variant, _single, _payload_widths and
  test_variant_self_assign_is_a_no_op -- emit a VALID module on it. This file
  does not: `wasm-validate` says `unable to read u32 leb128: local.set local
  index` and wasmtime refuses to compile function 238, while the pxx run still
  exits 0 and prints `ok:`.

  `after` is the row that always worked: a store first, then a box. It is here
  so a fix that allocates msval somewhere useless still has to keep this green.

  Cross rather than wasm32-only because the value is the language's: the
  register backends have no such locals and cannot fail this, and the row that
  fails on one target is still the one whose ANSWER all six must agree on. }
program test_cross_variant_boxed_string_no_store;

var
  gv: Variant;
  s: AnsiString;
  f: string[8];

procedure BoxAnsi(const a: AnsiString);
begin
  gv := a;
end;

procedure BoxFrozen(const a: string[8]);
begin
  gv := a;
end;

function MakeStr(k: Integer): AnsiString;
begin
  if k = 0 then MakeStr := 'call0' else MakeStr := 'call1';
end;

procedure BoxCallResult(k: Integer);
begin
  gv := MakeStr(k);
end;

procedure BoxAfterStore(const a: AnsiString);
var t: AnsiString;
begin
  t := 'pre-';
  gv := t + a;
end;

begin
  s := 'hello';
  f := 'froz';
  BoxAnsi(s);       Write('ansi   <'); Write(gv); WriteLn('>');
  BoxAnsi('');      Write('empty  <'); Write(gv); WriteLn('>');
  BoxFrozen(f);     Write('frozen <'); Write(gv); WriteLn('>');
  BoxCallResult(0); Write('call0  <'); Write(gv); WriteLn('>');
  BoxCallResult(1); Write('call1  <'); Write(gv); WriteLn('>');
  BoxAfterStore(s); Write('after  <'); Write(gv); WriteLn('>');
end.
