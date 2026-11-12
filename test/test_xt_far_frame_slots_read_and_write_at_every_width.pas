{ Locals and parameters placed far below the frame pointer, more than 128
  bytes past it and across several 256-byte steps, read and written at every
  width: byte, signed byte, word, signed word, longint, Int64, a pointer, a
  string, and a var param whose slot sits behind a big local block. On
  windowed xtensa these slots are reached with addmi plus the access
  immediate (XtFrameFar); everywhere else this is an ordinary program, and
  the x86-64 build is the oracle. }
program test_xt_far_frame_slots_read_and_write_at_every_width;

type
  TBig = array[0..99] of LongInt;

var
  gTotal: Int64;

procedure Bump(var x: LongInt; var q: Int64);
begin
  x := x + 7;
  q := q * 3 + 1;
end;

procedure FarSlots(n: LongInt; var outv: LongInt);
var
  pad1: TBig;
  b: Byte;
  sb: ShortInt;
  w: Word;
  sw: SmallInt;
  pad2: TBig;
  l: LongInt;
  q: Int64;
  p: PLongInt;
  pad3: TBig;
  s: AnsiString;
  c: Char;
  i: Integer;
begin
  for i := 0 to 99 do
  begin
    pad1[i] := i;
    pad2[i] := i * 2;
    pad3[i] := i * 3;
  end;
  b := 200 + n;
  sb := -100 - n;
  w := 60000 + n;
  sw := -30000 - n;
  l := 123456789 + n;
  q := Int64(9876543210) + n;
  p := @pad2[7];
  s := 'far';
  c := 'z';
  Writeln('R01 byte ', b, ' sbyte ', sb);
  Writeln('R02 word ', w, ' sword ', sw);
  Writeln('R03 long ', l, ' int64 ', q);
  Writeln('R04 ptr ', p^, ' str ', s, ' char ', c);
  b := b + 1; sb := sb - 1; w := w + 1; sw := sw - 1;
  l := l * 2; q := q * 2;
  s := s + '!' + s;
  Inc(c, -1);
  Bump(l, q);
  Writeln('R05 ', b, ' ', sb, ' ', w, ' ', sw);
  Writeln('R06 ', l, ' ', q);
  Writeln('R07 ', s, ' ', c, ' ', Length(s));
  Writeln('R08 pads ', pad1[99] + pad2[50] + pad3[1]);
  outv := outv + l;
  gTotal := gTotal + q;
end;

var
  r: LongInt;
begin
  r := 5;
  FarSlots(1, r);
  FarSlots(2, r);
  Writeln('R09 out ', r, ' total ', gTotal);
end.
