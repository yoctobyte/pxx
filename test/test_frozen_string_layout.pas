{ THE LAYOUT OF A FROZEN STRING, ASSERTED AS RELATIONS SO ONE .expected SERVES
  BOTH MODES AND FPC.

  Not one number appears in the compared output. A `string[N]`'s prefix is 8
  bytes (tyString/tyFixedString) or 1 (tyShortString, -dPXX_SHORTSTRING), its
  slot size is rounded up to that prefix's alignment, and FPC's own answer is a
  third set of numbers again -- so any row printing a size or an offset would
  need three expected files and would be asserting the layout it happens to have
  rather than the layout it must have. Every row here is a relation that must
  hold under all three, and FPC 3.2.2 is therefore a real oracle for this file:
  it compiles and runs it unmodified.

  THE PREFIX WIDTH IS TAKEN FROM THE LANGUAGE, NEVER FROM THE LAYOUT: `@s[1]`
  is where Pascal says the first character lives. Deriving it as
  `SizeOf(TS) - 10` was true until the slot gained alignment padding, and a
  derivation that stops being true is worse than a constant, because it keeps
  answering.

  WHAT EACH GROUP CAUGHT, all measured 2026-09-03:

  A/B  `array[0..3] of string[10]` strode 18 bytes in the default mode, so odd
       elements began 2 mod 4 and the 8-byte length word was unaligned: xtensa
       BUS-ERRORED on the store AND on Length(), both ABIs, while elements 0 and
       2 were fine. Only an odd element traps, so a repro without the aligned
       pair reads as "array element stores are broken on this backend".
  D    `record x, y: string[10]` under -dPXX_SHORTSTRING measured 16 bytes with
       y at offset 8: y OVERLAPPED x and writing y truncated x to seven
       characters. The field-size test named tyFixedString only, so the flag's
       kind fell through to a POINTER WIDTH.
  E/F  a truncating store into a `string[4]` FIELD wrote all eight source bytes
       under the flag -- past the field and into its neighbour, which came back
       holding a character from the source. The variable and array-element
       spellings of the same assignment truncate correctly, so only the field
       spelling could show it.
  G/H  `a[0][1]` read base+8 under the flag where the first character is at
       base+1: a blank instead of 'h', and `@a[0][1]` seven bytes past the
       character it names, while the variable, field and deref spellings were
       all correct.

  H is the strongest row and the cheapest: the first character's ADDRESS is one
  place under every spelling, so four spellings that disagree cannot all be
  right, and no expected value has to name where it is. }
program test_frozen_string_layout;
type
  TS10 = string[10];
  TS4  = string[4];
  TREC = record x, y: TS10; end;
  TMIX = record a: Byte; f: TS4; b: Byte; g: TS4; end;
var
  arr: array[0..3] of TS10;
  r: TREC;
  m: TMIX;
  s: TS10; p: ^TS10;
  i, stride, pfx, al: PtrUInt;
  ok: Boolean;

procedure Chk(const tag: AnsiString; cond: Boolean);
begin
  if cond then WriteLn('ok   ', tag) else WriteLn('FAIL ', tag);
end;

begin
  s := 'hello'; p := @s;
  for i := 0 to 3 do arr[i] := 'e';
  r.x := ''; r.y := '';

  { ---- A. stride IS SizeOf: the rule every Pascal program may assume ---- }
  stride := PtrUInt(@arr[1]) - PtrUInt(@arr[0]);
  Chk('stride equals SizeOf(element)', stride = PtrUInt(SizeOf(TS10)));
  Chk('stride is uniform across the array',
      (PtrUInt(@arr[2]) - PtrUInt(@arr[1]) = stride) and
      (PtrUInt(@arr[3]) - PtrUInt(@arr[2]) = stride));

  { ---- B. every element carries the prefix at its own alignment ----

    THE ALIGNMENT IS NOT THE PREFIX WIDTH, and asserting that it was is a
    32-bit-only failure that x86-64 cannot show: the 8-byte prefix is written as
    TWO machine words on a 32-bit target, so 4-alignment is what it needs and
    what it gets, and `stride mod 8` FAILED on i386, arm32, riscv32, wasm32 and
    xtensa while passing on x86-64 and aarch64. The requirement is the prefix
    width CAPPED AT A MACHINE WORD -- 8 on a 64-bit target, 4 on a 32-bit one,
    and 1 under -dPXX_SHORTSTRING, where a byte prefix needs no alignment at
    all and this row is correctly vacuous. }
  pfx := PtrUInt(@arr[0][1]) - PtrUInt(@arr[0]);
  al := pfx;
  if al > PtrUInt(SizeOf(Pointer)) then al := PtrUInt(SizeOf(Pointer));
  Chk('stride is a multiple of the prefix alignment', stride mod al = 0);
  ok := True;
  for i := 0 to 3 do
    if PtrUInt(@arr[i]) mod al <> 0 then ok := False;
  Chk('every element base is prefix-aligned', ok);

  { ---- C. and the odd elements are writable and independent ---- }
  arr[0] := 'zero'; arr[1] := 'one'; arr[2] := 'two'; arr[3] := 'three';
  Chk('all four elements read back', (arr[0] = 'zero') and (arr[1] = 'one') and
                                     (arr[2] = 'two') and (arr[3] = 'three'));
  Chk('lengths survive the round trip', (Length(arr[0]) = 4) and (Length(arr[1]) = 3) and
                                        (Length(arr[2]) = 3) and (Length(arr[3]) = 5));

  { ---- D. two frozen fields do not overlap ---- }
  r.x := 'AAAAAAAAAA';
  r.y := 'BBBBBBBBBB';
  Chk('second field does not clobber the first', r.x = 'AAAAAAAAAA');
  Chk('and the second field is itself', r.y = 'BBBBBBBBBB');
  Chk('fields are at least a slot apart',
      PtrUInt(@r.y) - PtrUInt(@r.x) >= PtrUInt(Length(r.x)) + pfx);

  { ---- E/F. a truncating store stays inside its field ---- }
  m.a := 1; m.b := 2; m.g := 'wxyz';
  m.f := 'abcdefgh';
  Chk('field store truncates to the declared capacity', m.f = 'abcd');
  Chk('and reports the truncated length', Length(m.f) = 4);
  Chk('the byte after the field is untouched', m.b = 2);
  Chk('the field after that is untouched', m.g = 'wxyz');
  s := 'abcdefghijklmno';
  Chk('a variable truncates the same way', (Length(s) = 10) and (s = 'abcdefghij'));
  arr[1] := 'abcdefghijklmno';
  Chk('an element truncates the same way', (Length(arr[1]) = 10) and (arr[1] = 'abcdefghij'));

  { ---- G/H. the first character is in ONE place, under every spelling ---- }
  s := 'hello'; arr[0] := 'hello'; r.x := 'hello';
  Chk('char index: variable', s[1] = 'h');
  Chk('char index: array element', arr[0][1] = 'h');
  Chk('char index: record field', r.x[1] = 'h');
  Chk('char index: pointer deref', p^[1] = 'h');
  Chk('first char offset: element agrees with variable',
      PtrUInt(@arr[0][1]) - PtrUInt(@arr[0]) = PtrUInt(@s[1]) - PtrUInt(@s));
  Chk('first char offset: field agrees with variable',
      PtrUInt(@r.x[1]) - PtrUInt(@r.x) = PtrUInt(@s[1]) - PtrUInt(@s));
  Chk('first char offset: deref agrees with variable',
      PtrUInt(@p^[1]) - PtrUInt(p) = PtrUInt(@s[1]) - PtrUInt(@s));

  { ---- MUST-DIFFER CONTROL: the rows above cannot be passing by reading one
         shared buffer. arr[2] holds different bytes and a different length. ---- }
  Chk('control: a neighbour still differs', (arr[2] = 'two') and (arr[0] <> arr[2]));
end.
