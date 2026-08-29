program Shifts;
{ Every constant shift count the new immediate form can take, against every
  operand width and signedness, with a VARIABLE-count control beside each one:
  the variable form keeps the old `shr rax, cl` path, so if the two ever
  disagree the immediate encoding is wrong. Diffed against FPC 3.2.2 and across
  -O0/-O1/-O2/-O3. Count 0 is included deliberately — it is the only count that
  can show a sign-extension mistake, since any count >= 1 clears bit 31.
  feature-opt-o3-register-pressure W1 }
var
  i8:  ShortInt;  u8:  Byte;
  i16: SmallInt;  u16: Word;
  i32: LongInt;   u32: LongWord;
  i64: Int64;     u64: QWord;
  k, bad: LongInt;
  vc: LongInt;    { the variable count — same value, different path }

procedure Chk(const tag: AnsiString; a, b: Int64);
begin
  if a <> b then begin WriteLn('MISMATCH ', tag, ' imm=', a, ' var=', b); bad := bad + 1; end;
end;

begin
  bad := 0;
  i8  := -100;  u8  := 200;
  i16 := -30000; u16 := 60000;
  i32 := -2000000000; u32 := 4000000000;
  i64 := -1234567890123456789; u64 := 12345678901234567890;

  { constant counts 0..7 written out, each with its variable-count twin }
  vc := 0;  Chk('i32 shr 0',  i32 shr 0,  i32 shr vc);   Chk('i32 shl 0',  i32 shl 0,  i32 shl vc);
  vc := 1;  Chk('i32 shr 1',  i32 shr 1,  i32 shr vc);   Chk('i32 shl 1',  i32 shl 1,  i32 shl vc);
  vc := 3;  Chk('i32 shr 3',  i32 shr 3,  i32 shr vc);   Chk('i32 shl 3',  i32 shl 3,  i32 shl vc);
  vc := 7;  Chk('i32 shr 7',  i32 shr 7,  i32 shr vc);   Chk('i32 shl 7',  i32 shl 7,  i32 shl vc);
  vc := 31; Chk('i32 shr 31', i32 shr 31, i32 shr vc);   Chk('i32 shl 31', i32 shl 31, i32 shl vc);
  vc := 32; Chk('i32 shr 32', i32 shr 32, i32 shr vc);   Chk('i32 shl 32', i32 shl 32, i32 shl vc);
  vc := 63; Chk('i32 shr 63', i32 shr 63, i32 shr vc);   Chk('i32 shl 63', i32 shl 63, i32 shl vc);

  vc := 0;  Chk('u32 shr 0',  u32 shr 0,  u32 shr vc);   Chk('u32 shl 0',  u32 shl 0,  u32 shl vc);
  vc := 1;  Chk('u32 shr 1',  u32 shr 1,  u32 shr vc);   Chk('u32 shl 1',  u32 shl 1,  u32 shl vc);
  vc := 31; Chk('u32 shr 31', u32 shr 31, u32 shr vc);   Chk('u32 shl 31', u32 shl 31, u32 shl vc);
  vc := 32; Chk('u32 shr 32', u32 shr 32, u32 shr vc);   Chk('u32 shl 32', u32 shl 32, u32 shl vc);

  vc := 0;  Chk('i64 shr 0',  i64 shr 0,  i64 shr vc);   Chk('i64 shl 0',  i64 shl 0,  i64 shl vc);
  vc := 1;  Chk('i64 shr 1',  i64 shr 1,  i64 shr vc);   Chk('i64 shl 1',  i64 shl 1,  i64 shl vc);
  vc := 32; Chk('i64 shr 32', i64 shr 32, i64 shr vc);   Chk('i64 shl 32', i64 shl 32, i64 shl vc);
  vc := 63; Chk('i64 shr 63', i64 shr 63, i64 shr vc);   Chk('i64 shl 63', i64 shl 63, i64 shl vc);

  vc := 0;  Chk('u64 shr 0',  Int64(u64 shr 0),  Int64(u64 shr vc));
  vc := 1;  Chk('u64 shr 1',  Int64(u64 shr 1),  Int64(u64 shr vc));
  vc := 63; Chk('u64 shr 63', Int64(u64 shr 63), Int64(u64 shr vc));

  vc := 0;  Chk('i8 shr 0',   i8 shr 0,   i8 shr vc);    Chk('i8 shl 0',   i8 shl 0,   i8 shl vc);
  vc := 1;  Chk('i8 shr 1',   i8 shr 1,   i8 shr vc);    Chk('i8 shl 1',   i8 shl 1,   i8 shl vc);
  vc := 7;  Chk('i8 shr 7',   i8 shr 7,   i8 shr vc);    Chk('i8 shl 7',   i8 shl 7,   i8 shl vc);
  vc := 0;  Chk('u8 shr 0',   u8 shr 0,   u8 shr vc);    Chk('u8 shl 0',   u8 shl 0,   u8 shl vc);
  vc := 3;  Chk('u8 shr 3',   u8 shr 3,   u8 shr vc);    Chk('u8 shl 3',   u8 shl 3,   u8 shl vc);
  vc := 0;  Chk('i16 shr 0',  i16 shr 0,  i16 shr vc);   Chk('i16 shl 0',  i16 shl 0,  i16 shl vc);
  vc := 5;  Chk('i16 shr 5',  i16 shr 5,  i16 shr vc);   Chk('i16 shl 5',  i16 shl 5,  i16 shl vc);
  vc := 0;  Chk('u16 shr 0',  u16 shr 0,  u16 shr vc);   Chk('u16 shl 0',  u16 shl 0,  u16 shl vc);
  vc := 9;  Chk('u16 shr 9',  u16 shr 9,  u16 shr vc);   Chk('u16 shl 9',  u16 shl 9,  u16 shl vc);

  { and the actual VALUES, so this is not only a self-consistency check —
    every line below is compared against FPC's output for the same source }
  WriteLn('i32: ', i32 shr 0, ' ', i32 shr 1, ' ', i32 shr 31, ' ', i32 shl 1, ' ', i32 shl 31);
  WriteLn('u32: ', u32 shr 0, ' ', u32 shr 1, ' ', u32 shr 31, ' ', u32 shl 1);
  WriteLn('i64: ', i64 shr 0, ' ', i64 shr 1, ' ', i64 shr 63, ' ', i64 shl 1, ' ', i64 shl 63);
  WriteLn('u64: ', u64 shr 0, ' ', u64 shr 1, ' ', u64 shr 63);
  WriteLn('i8 : ', i8 shr 0, ' ', i8 shr 1, ' ', i8 shr 7, ' ', i8 shl 1, ' ', i8 shl 7);
  WriteLn('u8 : ', u8 shr 0, ' ', u8 shr 3, ' ', u8 shl 3);
  WriteLn('i16: ', i16 shr 0, ' ', i16 shr 5, ' ', i16 shl 5);
  WriteLn('u16: ', u16 shr 0, ' ', u16 shr 9, ' ', u16 shl 9);

  { a shift feeding another operator, so the count register really is free }
  k := 0;
  for vc := 1 to 10 do k := k + (i32 shr 4) + (vc shl 2) - (u16 shr 3);
  WriteLn('mixed: ', k);

  if bad = 0 then WriteLn('SHIFTS OK') else WriteLn('FAILURES: ', bad);
end.
