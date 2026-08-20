program test_unary_minus_widens_to_int64;
{ FPC's unary minus has ONE result type: `SizeOf(-x)` is 8 for EVERY integer
  operand — Byte, ShortInt, Word, SmallInt, Integer, Cardinal, Int64, QWord,
  NativeInt, NativeUInt alike. Measured, not assumed.

  pxx used to carry the operand's own type onto the AN_NEG node, which is right
  for a float and wrong for an unsigned integer: `-b` on a Byte was evaluated as
  an unsigned 32-bit 4294967288 and only widened afterwards, so `-b shr 1`
  answered 2147483644 ($7FFFFFFC, a 32-bit logical shift of $FFFFFFF8) where FPC
  says 9223372036854775804. The sign was gone before the shift ran, which is why
  the shift path was never where this could be fixed.

  In the DEFAULT dialect, not behind --strict-fpc: a silent wrong value is a bug,
  not parity work (decide-unary-minus-widening-in-the-default-dialect, owner
  2026-08-19). bug-p-unary-minus-on-an-unsigned-operand-truncates-to-32-bits

  Every expected value below is FPC 3.2.2 -O1's own answer. }
{$mode objfpc}{$H+}
uses SysUtils;

var
  ok, total: Integer;

procedure Check(const nm: AnsiString; got, want: Int64);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', nm, ': got ', got, ' want ', want);
end;

{ `-x` now selects an Int64-taking candidate where `x` alone selects the
  narrower one — the overload-resolution half the decision flagged. }
function Pick(x: Integer): AnsiString; overload; begin Result := 'Integer'; end;
function Pick(x: Int64): AnsiString; overload; begin Result := 'Int64'; end;
function Pick(x: Double): AnsiString; overload; begin Result := 'Double'; end;

procedure CheckS(const nm, got, want: AnsiString);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', nm, ': got ', got, ' want ', want);
end;

const
  NEG8SHR1 = 9223372036854775804;  { -8 as an Int64, shifted right one }

var
  b: Byte; si: ShortInt; w: Word; sm: SmallInt; i: Integer; c: Cardinal;
  q: Int64; qw: QWord; ni: NativeInt; nu: NativeUInt; ch: Char;
  d: Double; s: Single;
  qLow, sink: Int64; raised: Boolean;
begin
  ok := 0; total := 0;

  b := 8; si := 8; w := 8; sm := 8; i := 8; c := 8;
  q := 8; qw := 8; ni := 8; nu := 8; ch := #8;

  { The seven-row table from the ticket: the unsigned rows were the wrong ones. }
  Check('Byte',       -b shr 1,  NEG8SHR1);
  Check('ShortInt',   -si shr 1, NEG8SHR1);
  Check('Word',       -w shr 1,  NEG8SHR1);
  Check('SmallInt',   -sm shr 1, NEG8SHR1);
  Check('Integer',    -i shr 1,  NEG8SHR1);
  Check('Cardinal',   -c shr 1,  NEG8SHR1);
  Check('Int64',      -q shr 1,  NEG8SHR1);
  { ...and the three the ticket did not table, measured the same way. }
  Check('QWord',      -qw shr 1, NEG8SHR1);
  Check('NativeInt',  -ni shr 1, NEG8SHR1);
  Check('NativeUInt', -nu shr 1, NEG8SHR1);
  Check('Char',       -Ord(ch) shr 1, NEG8SHR1);

  { The widening must not disturb the ordinary value of a negation. }
  Check('plain Byte',     -b,  -8);
  Check('plain Cardinal', -c,  -8);
  Check('plain Int64',    -q,  -8);
  Check('twice',          -(-b), 8);
  Check('in arithmetic',  10 + -b, 2);
  Check('back into Byte', Byte(-b + 16), 8);

  { `and` is the other operator that exposes the binding, and it must still see
    a 64-bit negative left operand. }
  Check('and',  -i and 12, 8);   { -8 and 12 = 8; the ticket's own row }

  { Overload resolution moves with the type — that is intended, and it is what
    FPC does. }
  CheckS('Pick(b)',   Pick(b),   'Integer');
  CheckS('Pick(-b)',  Pick(-b),  'Int64');
  CheckS('Pick(i)',   Pick(i),   'Integer');
  CheckS('Pick(-i)',  Pick(-i),  'Int64');
  CheckS('Pick(q)',   Pick(q),   'Int64');
  CheckS('Pick(-q)',  Pick(-q),  'Int64');

  { A FLOAT operand keeps its own type — the widening is integer-only. }
  d := 8.5; s := 2.5;
  CheckS('Pick(-d)', Pick(-d), 'Double');
  Check('float neg', Trunc(-d * 2), -17);
  Check('single neg', Trunc(-s * 2), -5);

  { {$Q+}: FPC checks unary minus too. After the widening, -Low(Int64) is the
    ONLY negation that can overflow — every narrower operand widens to Int64
    first, where its negation always fits. }
  qLow := Low(Int64);
  raised := False;
  {$Q+}
  try
    { Into a variable rather than a writeln: the raise happens while evaluating
      the argument, so a writeln would already have emitted its prefix and
      glued it to the next line. `sink` is read afterwards so nothing folds it
      away. }
    sink := -qLow;
    if sink = 1 then writeln('unreachable');
  except
    on E: EIntOverflow do raised := True;
  end;
  {$Q-}
  total := total + 1;
  if raised then ok := ok + 1
  else writeln('FAIL Q+ neg Low(Int64): no EIntOverflow raised');

  { ...and the narrow types must NOT trap under {$Q+}, because they widen. }
  b := 200; c := 4000000000; i := Low(Integer);
  {$Q+}
  Check('Q+ neg Byte 200',       -b, -200);
  Check('Q+ neg Cardinal 4e9',   -c, -4000000000);
  Check('Q+ neg Low(Integer)',   -i, 2147483648);
  {$Q-}

  writeln('total ok ', ok, ' / ', total);
end.
