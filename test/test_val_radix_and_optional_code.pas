program test_val_radix_and_optional_code;
{ Val's RADIX PREFIXES and its optional third argument. Every value below is
  FPC 3.2.2's on this same source.

  `Val('$ff', v, code)` answered 0 with code=1 — none of FPC's prefixes were
  accepted, and `$` is how Pascal source itself spells hex, so a config or
  script reading such a number got a silent 0 and a code its caller usually
  ignores. `Val(s, v)` — the two-argument form, which is ordinary FPC code —
  was refused outright with "Expected: ,".

  The failure ROWS matter as much as the successes: FPC reports the 1-based
  position of the character that stopped it, and a bare prefix with no digits
  stops one past itself.
  bug-p-val-rejects-the-radix-prefixes }

var
  okc, total: Integer;

procedure ChkV(const src: string; wantV: Int64; wantC: Integer);
var v: Int64; c: Integer;
begin
  Inc(total);
  v := -1; c := -1;
  Val(src, v, c);
  if (v = wantV) and (c = wantC) then begin Inc(okc); WriteLn('ok ', src); end
  else WriteLn('FAIL ', src, ' got ', v, '/', c, ' want ', wantV, '/', wantC);
end;

var
  i: Integer;
  d: Double;
  q: QWord;
begin
  okc := 0; total := 0;

  { hex, three spellings }
  ChkV('$ff', 255, 0);
  ChkV('xFF', 255, 0);
  ChkV('0xFF', 255, 0);
  ChkV('0X1f', 31, 0);
  ChkV('$FFFFFFFFFFFFFFFF', -1, 0);   { wraps, as FPC's does }
  { octal and binary }
  ChkV('&17', 15, 0);
  ChkV('%1011', 11, 0);
  { signs and leading blanks compose with a prefix }
  ChkV('-$10', -16, 0);
  ChkV('+$10', 16, 0);
  ChkV('  $10', 16, 0);
  { the failure rows }
  ChkV('$', 0, 2);
  ChkV('%', 0, 2);
  ChkV('$1g', 0, 3);
  ChkV('%12', 0, 3);
  ChkV('abc', 0, 1);
  { plain decimal is unchanged by any of it }
  ChkV('123', 123, 0);
  ChkV('-45', -45, 0);
  ChkV('09', 9, 0);
  ChkV('0', 0, 0);

  { the optional code argument, for each destination kind }
  Inc(total); i := 99; Val('7', i);
  if i = 7 then begin Inc(okc); WriteLn('ok two-arg-int'); end
  else WriteLn('FAIL two-arg-int got ', i);

  Inc(total); d := 9; Val('2.5', d);
  if d = 2.5 then begin Inc(okc); WriteLn('ok two-arg-float'); end
  else WriteLn('FAIL two-arg-float');

  Inc(total); q := 5; Val('12', q);
  if q = 12 then begin Inc(okc); WriteLn('ok two-arg-qword'); end
  else WriteLn('FAIL two-arg-qword');

  { a FAILED two-arg conversion zeroes the destination and raises nothing }
  Inc(total); i := 99; Val('zz', i);
  if i = 0 then begin Inc(okc); WriteLn('ok two-arg-fail'); end
  else WriteLn('FAIL two-arg-fail got ', i);

  WriteLn('total ok ', okc, ' / ', total);
end.
