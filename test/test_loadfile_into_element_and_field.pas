program test_loadfile_into_element_and_field;
{ LoadFile's destination may be an ARRAY ELEMENT or a RECORD FIELD, not only a
  plain variable. The intrinsic (`specialId = 100`, ir_codegen.inc) matched its
  destination as a symbol and rejected anything else with "LoadFile expects
  string variables in IR codegen" — a restriction in the INTRINSIC, never in the
  language: an ordinary `procedure F(var s: AnsiString)` has always accepted
  `arr[1]`.

  The destination arrives wrapped in an IR_LOAD_MEM (the frontend lowers this
  argument as a value expression, which is also why a plain variable arrives as
  IR_LOAD_SYM rather than IR_LEA); the IR_INDEX/IR_FIELD underneath is the
  address of the managed-string slot.

  Row 4 is the one that catches a bad publish rather than a bad match: it
  republishes over a slot that already holds a string, which must RELEASE the
  old handle. Measured before this test existed — 500 republishes of a 264 KB
  file peak at 512 KB RSS, where a leak would be ~132 MB.
  bug-a-c-preprocessor-include-buffers-are-sixteen-globals-not-an-array

  THE PATH HALF (rows pelem/pdyn/pfld), 2026-09-19: the PATH goes through the
  same lvalue door, and x86-64 read an element/field path as if its operand
  were a symbol index -- a segfault in a plain program and an EMPTY READ inside
  the compiler, where it stopped the Route 2 linker re-reading its objects.
  Each live path is placed LAST among entries naming files that do not exist,
  so reading the wrong element prints 0 rather than 14 -- and 0 is also what a
  garbage handle read, so the expected 14 cannot collide with either failure. }
var
  arr: array[0..3] of AnsiString;
  rec: record s: AnsiString; end;
  plain, p: AnsiString;
  i: Integer;
  paths: array[0..2] of AnsiString;
  dpaths: array of AnsiString;
  prec: record miss, hit: AnsiString; end;
  got: AnsiString;
begin
  p := 'test/test_loadfile_into_element_and_field.data';
  LoadFile(p, plain);
  LoadFile(p, arr[2]);
  LoadFile(p, rec.s);
  WriteLn('plain ', Length(plain));
  WriteLn('elem  ', Length(arr[2]));
  WriteLn('field ', Length(rec.s));
  { neighbouring slots must be untouched — a publish to the wrong address
    would most likely land in one of them }
  WriteLn('nbrs  ', Length(arr[1]), ' ', Length(arr[3]));
  { republish over a live slot: the old handle must be released, and the
    content must be the file rather than a fragment of the previous one }
  for i := 1 to 50 do LoadFile(p, arr[2]);
  WriteLn('again ', Length(arr[2]));
  paths[0] := p + '.absent0'; paths[1] := p + '.absent1'; paths[2] := p;
  LoadFile(paths[2], got);
  WriteLn('pelem ', Length(got));
  SetLength(dpaths, 3);
  dpaths[0] := p + '.absent0'; dpaths[1] := p + '.absent1'; dpaths[2] := p;
  LoadFile(dpaths[2], got);
  WriteLn('pdyn  ', Length(got));
  prec.miss := p + '.absent'; prec.hit := p;
  LoadFile(prec.hit, arr[3]);
  WriteLn('pfld  ', Length(arr[3]));
end.
