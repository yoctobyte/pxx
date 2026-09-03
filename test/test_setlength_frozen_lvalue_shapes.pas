program test_setlength_frozen_lvalue_shapes;
{ SetLength on a FROZEN string reached through something other than a plain
  symbol. `SetLength(p^, n)`, `SetLength(r.f, n)` and `SetLength(arr[i], n)`
  were all refused -- the first two with `SetLength expects a string variable
  in IR codegen`, the ELEMENT with `SetLength expects an ARRAY variable`,
  because the classifier's AN_INDEX arm answered "array" without asking what
  the element was and sent it to the dynamic-array builtin.

  THE MANAGED ROWS ARE THE ORACLE AND THEY ALWAYS PASSED: symbol, field and
  element all work for AnsiString through IR_SETLEN_STR, so this file asserts
  the frozen half against a mechanism that was already right beside it. wasm32
  was the second oracle -- its -101 arm has always been address-based and ran
  all three shapes before the fix.

  The GUARD columns are not decoration. A frozen string's length prefix sits
  inside the slot, so a store at the wrong address or the wrong WIDTH lands in
  the NEIGHBOUR -- the failure mode of the byte-prefix work throughout. sa[1]
  and da[1] are those neighbours, and they are read back after every write.

  Values verified byte-identical against FPC 3.2.2 and on seven targets in both
  prefix modes (xtensa under --xtensa-soft-mulhigh, which the emulator needs
  for any numeric output).
  bug-a-setlength-is-refused-for-any-frozen-string-that-is-not-a-plain-symbol }
type
  TS10 = string[10];
  TRec = record f: TS10; end;
var
  r: TRec; sa: array[0..1] of TS10; da: array of TS10; p: ^TS10; s: TS10;
  ms: AnsiString; msa: array[0..1] of AnsiString;
  nest: array of array of TS10;
begin
  SetLength(da, 2);
  s := 'abcdefg'; r.f := 'hijklmn';
  sa[0] := 'opqrstu'; sa[1] := 'GUARD';
  da[0] := 'vwxyzAB'; da[1] := 'DGUARD';
  p := @s;

  SetLength(s, 3);     WriteLn('sym   ', Length(s), ' ', s);
  SetLength(p^, 2);    WriteLn('deref ', Length(s), ' ', s);
  SetLength(r.f, 3);   WriteLn('field ', Length(r.f), ' ', r.f);
  SetLength(sa[0], 4); WriteLn('selem ', Length(sa[0]), ' ', sa[0], ' g=', sa[1]);
  SetLength(da[0], 5); WriteLn('delem ', Length(da[0]), ' ', da[0], ' g=', da[1]);

  { THE COUNTER-CASE, and it is the row that keeps the fix honest. `x[0]` on a
    depth-2 dynamic array is a SUB-ARRAY, not a string, even though its element
    kind is frozen -- so the classifier must answer "array" here and "string"
    for `sa[0]` above. Asking only "is the element frozen" sends this one to the
    string arm, which writes a length prefix over the sub-array's handle and
    segfaults. It did, on origin, for one commit. }
  SetLength(nest, 2); SetLength(nest[0], 2); SetLength(nest[1], 1);
  nest[0][0] := 'n00'; nest[0][1] := 'n01'; nest[1][0] := 'GUARD';
  WriteLn('nest  ', Length(nest), ' ', Length(nest[0]), ' ', nest[0][0], ' ', nest[0][1], ' g=', nest[1][0]);

  ms := 'managed';     SetLength(ms, 3);     WriteLn('msym  ', Length(ms), ' ', ms);
  msa[0] := 'mgdelem'; SetLength(msa[0], 3); WriteLn('melem ', Length(msa[0]), ' ', msa[0]);
end.
