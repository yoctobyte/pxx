{ The two readers that survived the four-cause frozen-prefix fix 764dc3a30, and
  the four causes behind them -- all one sentence, `= tyString` where the code
  meant TypeIsFrozenString.

  EVERY ROW HERE HAS A NEGATIVE PARTNER. A comparison bug in this family fails
  by answering a CONSTANT: the pre-fix field compare segfaulted, but the pre-fix
  field-vs-field compare answered TRUE for every input because it compared two
  loaded words, and a suite of "must be TRUE" rows would have certified it. So
  each `= 'hello'` is paired with an `= 'nope'` that must be FALSE.

  THE DEREF ROWS ASSERT THE WRITE, NOT ONLY THE READ. `p^[1] := 'H'` stored at
  base+8 before the fix: inside the slot, nothing visibly corrupted, and the
  assignment silently discarded. A read-only test passes against that.

  bug-a-indexing-a-frozen-string-through-a-pointer-deref-reads-the-wrong-byte
  bug-a-comparing-a-frozen-record-field-to-a-literal-crashes-or-answers-false }
program test_frozen_field_and_deref_readers;
type
  TS10 = string[10]; PS10 = ^TS10;
  TR = record f: TS10; g: TS10; end;
var
  r, t: TR; s: TS10; p: PS10; i: Integer;
begin
  r.f := 'hello'; r.g := 'hello'; t.f := 'world'; s := 'hello'; p := @s;

  { the variable spelling -- green throughout, so it is the control that says
    the harness is pointed at a working case too }
  WriteLn('var  ', s = 'hello', ' ', s = 'nope');
  { the FIELD spelling: segfaulted on x86-64/riscv32, FALSE on aarch64/arm32 }
  WriteLn('fld  ', r.f = 'hello', ' ', r.f = 'nope');
  { the DEREF spelling }
  WriteLn('drf  ', p^ = 'hello', ' ', p^ = 'nope');
  { field against a VARIABLE -- no literal operand to drag the guard true }
  WriteLn('fv   ', r.f = s, ' ', t.f = s);
  { field against FIELD -- the row CmpFusible fused into a scalar address cmp,
    correct at -O0 and FALSE at -O1+ }
  WriteLn('ff   ', r.f = r.g, ' ', r.f = t.f);
  WriteLn('ne   ', r.f <> 'nope', ' ', r.f <> 'hello');

  { indexing: the same fact reached through three shapes, one of which was wrong }
  WriteLn('idx  [', s[1], r.f[1], p^[1], ']');
  WriteLn('len  ', Length(s), Length(r.f), Length(p^));
  { index 0 is the length byte and has its own origin -- it was always right,
    so it is here to stay right }
  WriteLn('len0 ', Ord(p^[0]));

  { THE WRITE HALF }
  p^[1] := 'H';
  WriteLn('wr   [', s, ']');

  for i := 1 to 5 do Write(r.f[i]);
  WriteLn;
end.
