{ wasm32 lowers write/writeln onto builtinheap's PXXWrite* family, and a
  Pascal program that only writes never pulled builtinheap: `writeln(6*7)`
  emitted main as `unreachable`, printed `ok:` with rc=0 and trapped under
  wasmtime. Run on wasm32, compared byte-for-byte with the x86-64 build.
  NO `:w` FORMAT SPEC here: that pulls builtinheap on every target by its own
  arm, and with one in the file the pin passes this test. }
program test_wasm32_writeln_of_an_ordinal_builds_and_prints;
var i: Integer; b: Boolean; c: Char;
begin
  writeln(6*7);
  i := -5; b := True; c := 'x';
  writeln(i, ' ', b, ' ', c);
end.
