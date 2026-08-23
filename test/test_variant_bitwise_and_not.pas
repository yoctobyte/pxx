program test_variant_bitwise_and_not;
{ Bitwise operators and unary `not` on a Variant, against fpc 3.2.2 -Mobjfpc.

  Three defects met here, all of them one concept implemented twice:

    * `not v` was lowered as Python TRUTHINESS for every tag, so `not v` with
      v = 12 answered False -- the wrong VALUE and the wrong TYPE, and every
      downstream use of `mask := not flags` was wrong without ever mentioning
      `not`. Pascal picks bitwise-vs-logical from the OPERAND, which on a
      Variant only the runtime tag knows.
    * `v shr 1` was refused outright ("Variant arithmetic: unsupported
      operator"): Pascal spells `shr` as an identifier, and the variant
      lowering was the one consumer of that convention that did not know it.
    * every bitwise op returned STACK GARBAGE on i386 / arm32 / aarch64 --
      x86-64's inline emitter implemented them and the runtime dispatch every
      other target uses did not, so its if-chain ran off the end. `v(12) and
      v(10)` answered -524095488 / 1082138624 / 4358436 for the source that
      gives 8 here.

  bug-a-not-on-an-integer-variant-answers-a-boolean

  Deliberately NOT covered: `writeln` of a Boolean Variant prints 1/0 rather
  than True/False on every target except x86-64 -- a separate, pre-existing
  defect (bug-a-a-boolean-variant-writes-as-1-or-0-off-x86-64), so this test
  reads tags and values instead of rendering them.
  Also not covered: `v(-12) shr 1`. Pascal's shr is logical, x86-64 emits an
  arithmetic sar, and FPC narrows a Variant to 32 bits first and answers
  2147483642 -- three answers, parked as decide-variant-bitwise-width. Every
  non-negative row below agrees under all three readings. }
uses variants;
var
  a, b, c: Variant;
  fails: Integer;

procedure ChkI(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  a := 12; b := 10;

  ChkI('and', a and b, 8);
  ChkI('or', a or b, 14);
  ChkI('xor', a xor b, 6);
  ChkI('shl', a shl 1, 24);
  { `shr` is the row that used to refuse to COMPILE }
  ChkI('shr', a shr 1, 6);

  { the arithmetic siblings, so a change to the operator table cannot quietly
    lose them the way the bitwise ones were lost }
  ChkI('add', a + b, 22);
  ChkI('sub', a - b, 2);
  ChkI('mul', a * b, 120);
  ChkI('div', a div b, 1);
  ChkI('mod', a mod b, 2);
  ChkI('neg', -a, -12);

  { unary not: BITWISE on an integer }
  c := not a;
  ChkI('not 12', c, -13);
  a := 0;
  c := not a;
  ChkI('not 0', c, -1);

  { unary not: LOGICAL on a Boolean, and the result stays a Boolean.
    varBoolean = 11 in the FPC-compatible VarType() codes. }
  a := True;
  c := not a;
  if VarType(c) <> VarType(a) then
  begin
    writeln('FAIL not True: tag changed');
    fails := fails + 1;
  end;
  if c <> False then
  begin
    writeln('FAIL not True: not False');
    fails := fails + 1;
  end;
  a := False;
  c := not a;
  if c <> True then
  begin
    writeln('FAIL not False: not True');
    fails := fails + 1;
  end;

  { a float operand is ROUNDED before a bitwise op, as FPC does: 1.5 -> 2.
    Truncating answered 0 for the first row and -2 for the second. }
  a := 1.5; b := 10;
  ChkI('float and', a and b, 2);
  c := not a;
  ChkI('float not', c, -3);

  { negative operands: and/shl agree with FPC at any width }
  a := -12; b := 10;
  ChkI('neg and', a and b, 0);
  ChkI('neg shl', a shl 1, -24);

  if fails = 0 then writeln('ALL OK') else writeln(fails, ' FAILURES');
end.
