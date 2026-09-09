program test_booleannn_family;
{ fpc ships TWO sized-boolean families and pxx shipped one. `ByteBool` /
  `WordBool` / `LongBool` / `QWordBool` are C-ABI booleans; `Boolean16` /
  `Boolean32` / `Boolean64` are PASCAL booleans of a larger size, and the three
  latter names were `unknown type`.

  THE TWO FAMILIES DIFFER IN EXACTLY TWO THINGS and share everything else, so
  this file asserts both halves of the pair on every row that can tell them
  apart:

    Ord(True)           1 here, all-bits-set (-1) there
    the ordinal's sign  UNSIGNED here, SIGNED there

  THE SIGNEDNESS ROW NEEDS A VALUE ABOVE THE SIGNED RANGE OR IT CANNOT FAIL.
  `Boolean16(200)` and `WordBool(200)` both answer 200 — 200 fits a signed
  16-bit, so the row that was supposed to separate the families agrees on both.
  65535 is the discriminator and it is why the cast rows use it. That is the
  same trap ByteBool's own comment in pasparser_lval.inc records one family
  over (200 vs 255), and CLAUDE.md states it generally: choose a probe whose
  right answer differs from the failure value.

  AND THE ORD ROWS ARE READ THROUGH Int64(), NOT BARE. `Ord` and `WriteLn`
  truncate to the type's width, which is exactly how this subsystem's prior got
  poisoned once already: High/Low of the sized booleans were recorded — in a
  ticket AND in a compiler comment — as fpc answering TRUE/FALSE and agreeing
  with us, from a WriteLn readout, when fpc actually answers the Int64 extremes.
  Widen the readout before recording a row as parity.

  Everything else is shared and is asserted as such: width from the name,
  nonzero-is-true for `if` / `not` / `WriteLn`, and Low = False in both
  families.

  .expected IS fpc 3.2.2's own output on this source, unmodified.
  feature-p-the-booleannn-family-of-explicit-width-boolean-type-names }
{$mode objfpc}
var
  b16: Boolean16; b32: Boolean32; b64: Boolean64;
  wb: WordBool; lb: LongBool; qb: QWordBool; b: Boolean;
  w: Word;
begin
  { width comes from the name in both families }
  WriteLn('sizes   b16=', SizeOf(b16), ' b32=', SizeOf(b32), ' b64=', SizeOf(b64),
          '  wb=', SizeOf(wb), ' lb=', SizeOf(lb), ' qb=', SizeOf(qb), ' b=', SizeOf(b));

  { True materialises differently — the first of the two real differences }
  b16 := True; b32 := True; b64 := True;
  WriteLn('True    b16=', Int64(Ord(b16)), ' b32=', Int64(Ord(b32)), ' b64=', Int64(Ord(b64)));
  wb := True; lb := True; qb := True;
  WriteLn('True    wb=', Int64(Ord(wb)), ' lb=', Int64(Ord(lb)), ' qb=', Int64(Ord(qb)));

  { ...and False is 0 in both, which is the control that says the row above is
    about True and not about the storage kind }
  b16 := False; wb := False;
  WriteLn('False   b16=', Int64(Ord(b16)), '  wb=', Int64(Ord(wb)));

  { the ordinal's SIGN — the second real difference. 65535, not 200. }
  w := 65535; b16 := Boolean16(w); wb := WordBool(w);
  WriteLn('<-65535 b16=', Int64(Ord(b16)), '  wb=', Int64(Ord(wb)));

  { shared: nonzero is true, at all three surfaces, on a value that is neither
    1 nor all-bits-set in one of the two families }
  WriteLn('write   b16=', b16, '  wb=', wb);
  WriteLn('not     b16=', not b16, '  wb=', not wb);
  if b16 then WriteLn('if b16  : taken') else WriteLn('if b16  : NOT taken');
  if not b16 then WriteLn('if !b16 : taken') else WriteLn('if !b16 : NOT taken');

  { High/Low follow the True convention, and Low is False in both }
  WriteLn('bounds  b16 H=', Int64(Ord(High(Boolean16))), ' L=', Int64(Ord(Low(Boolean16))),
          '  b64 H=', Int64(Ord(High(Boolean64))), ' L=', Int64(Ord(Low(Boolean64))));
  { WordBool only. QWordBool's bounds are a CHOSEN divergence and belong to the
    other family's ticket, not this one -- fpc answers the Int64 extremes for
    every *Bool width, we answer True/False, and at widths 1/2/4 the extremes
    TRUNCATE to exactly our -1/0 so the two agree by coincidence. AT WIDTH 8
    THERE IS NOTHING LEFT TO TRUNCATE and the divergence becomes visible:
    fpc prints 9223372036854775807 / -9223372036854775808 where we print -1 / 0.
    Measured 2026-09-09. That is the same coincidence that made a WriteLn probe
    report parity on this subsystem once before, and QWordBool is the width
    where it stops -- see SizedBoolBound in pasparser_lval.inc. }
  WriteLn('bounds  wb  H=', Int64(Ord(High(WordBool))),  ' L=', Int64(Ord(Low(WordBool))));

  { a bound carries the named type's WIDTH, not the ordinal's — the row that
    fails if High() ever starts answering from a bare kind again }
  WriteLn('szbnd   b16=', SizeOf(High(Boolean16)), ' b32=', SizeOf(High(Boolean32)),
          ' b64=', SizeOf(High(Boolean64)), '  wb=', SizeOf(High(WordBool)));

  { Assignable from its own bounds. PASCAL FAMILY ONLY, and the omission is the
    interesting half: `wb := High(WordBool)` COMPILES HERE AND FPC REFUSES IT --
    *"Asm: word value exceeds bounds 9223372036854775807"* -- because fpc's
    High(WordBool) is the Int64 extreme and its own assembler will not store the
    value its own front end just produced. Measured 2026-09-09 while writing
    this file, which is the pathology SizedBoolBound's comment in
    pasparser_lval.inc predicted from the other direction.
    Us accepting what fpc rejects is not a defect (CLAUDE.md), but it is not
    ASSERTABLE in a file whose header claims it compiles under fpc unmodified --
    so the row is described here and not written. }
  b16 := High(Boolean16);
  WriteLn('assign  b16=', b16, ' ord=', Int64(Ord(b16)));
end.
