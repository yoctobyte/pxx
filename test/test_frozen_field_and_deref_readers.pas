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
  TWide = string[300];
var
  r, t: TR; s: TS10; p: PS10; i: Integer;
  a8: array[0..2] of string[8];
  a4: array[0..1] of string[4];
  w: TWide; n10: TS10;

{ A `const` frozen-string parameter is passed BY REFERENCE and read through the
  PARAMETER's prefix width, so an argument of a different width is read at one
  size and its payload at another. `const` guards against ALIASING, never
  against LAYOUT -- which is why the by-value copy funnel's `const` escape
  hatch was correct for years and stopped being correct the moment
  -dPXX_SHORTSTRING made two widths exist. }
procedure CNarrow(const n: TS10);
begin
  WriteLn('cp1  [', n, '] ', n = 'hello', ' ', n = 'nope');
end;

procedure CWide(const n: TWide);
begin
  WriteLn('cp3  ', Length(n), ' ', n = 'hello', ' ', n = 'nope');
end;

begin
  r.f := 'hello'; r.g := 'hello'; t.f := 'world'; s := 'hello'; p := @s;
  a8[0] := 'zero'; a8[1] := 'one'; a8[2] := 'two';
  a4[0] := 'ab'; a4[1] := 'cd';

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

  { ARRAY ELEMENTS. The store wrote an 8-byte length word into slots laid out
    at the byte-prefix stride, so each element's prefix overwrote the previous
    element's characters.

    ASSERT THE VALUE, NEVER THE LENGTH, and these rows are shaped for that.
    a[0] reported the RIGHT length beside destroyed data; a[2] -- the last
    element, with nothing after it to overwrite it -- read back correctly; and
    on the 32-bit targets a length read from the wrong offset TRUNCATED INTO THE
    CORRECT ANSWER (0x20000000002 has low 32 bits of exactly 2). So a Length()
    probe passes on i386/arm32/riscv32 with the bug fully present, and a
    last-element probe passes everywhere. Only the characters and the compare
    separate them. }
  WriteLn('arr  [', a8[0], '|', a8[1], '|', a8[2], ']');
  WriteLn('arrn [', a4[0], '|', a4[1], ']');
  WriteLn('arrc ', a8[1] = 'one', ' ', a8[1] = 'nope');

  { ORDERING. Equality survives a wrong prefix width -- both operands are read
    at the same wrong offset, so `=` still answers correctly on the wrong bytes.
    Only ordering, which walks characters from prefix+0, shows it. That is why
    `a = b` was green beside `a < b` answering FALSE for every input.

    TWO OF THE THREE NATURAL PAIRS ARE RIGHT BY ACCIDENT: a content-blind
    comparison answers `lt=FALSE gt=TRUE` always, which is CORRECT for any pair
    whose true answer is that. Both directions must be asserted, and the EQUAL
    pair is the sharpest row of the three -- for two identical strings both `<`
    and `>` must be FALSE, which no address comparison can produce. }
  WriteLn('lt1  ', s < 'hello', ' ', s > 'hello');
  a4[0] := 'abc'; a4[1] := 'abd';
  WriteLn('lt2  ', a4[0] < a4[1], ' ', a4[0] > a4[1]);
  WriteLn('lt3  ', a4[1] < a4[0], ' ', a4[1] > a4[0]);
  a4[1] := 'abc';
  WriteLn('lt4  ', a4[0] < a4[1], ' ', a4[0] > a4[1], ' ', a4[0] = a4[1]);

  { CONST PARAM, cross-width. Assert the VALUE, never only the length: the
    narrowing direction keeps a CORRECT length -- 5 is the low byte of the
    8-byte length word on a little-endian target -- while the payload reads as
    NUL bytes, so a Length()-only row passes with the bug fully present. Five
    NULs also render as an empty field in a terminal, which reads as a
    formatting quirk rather than as corruption.

    BOTH DIRECTIONS ARE ASSERTED, because they fail for different reasons and
    a fix for one left the other broken. Narrowing (cp1/cp2) is a literal or a
    wide variable into a 1-byte-prefix parameter. Widening (cp3) is a narrow
    variable into an 8-byte-prefix one -- and that row is the one that catches
    a width test asking ASTTk instead of the symbol, because a narrow
    variable's NODE carries the legacy tyString alias whose prefix is 8, which
    MATCHES a wide parameter and skips the copy. It answered
    Length = 122511465736197.

    A FRESH narrow variable, not `s`: the deref-write row above stores 'H'
    THROUGH p into s, so `s = 'hello'` is legitimately FALSE by this point and
    a row reading it would assert the wrong thing for the right reason. }
  w := 'hello'; n10 := 'hello';
  CNarrow('hello');   { literal (8-byte prefix) -> narrow const }
  CNarrow(w);         { wide var (8-byte prefix) -> narrow const, printed cp1 }
  CWide(n10);         { narrow var (1-byte prefix) -> wide const }

  { THE DIRECT WRITE, which is a THIRD reader and not covered by any row above.
    `Length(p^)`, `p^ = 'hello'`, `p^[1]` and `t := p^` were all correct in the
    same binary while `Write(p^)` printed a huge length followed by NUL bytes,
    because those four resolve the pointee through PtrElemTk and the writer
    instead consumes the operand node as a bare address. Re-pointed at n10, so
    this does not read the `s` that the deref-WRITE row above stores 'H' into. }
  p := @n10;
  WriteLn('drfw [', p^, ']');

  for i := 1 to 5 do Write(r.f[i]);
  WriteLn;
end.
