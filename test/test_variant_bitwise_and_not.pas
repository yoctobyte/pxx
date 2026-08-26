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
  A NEGATIVE `shr` is covered now, and it is the fourth defect of the same
  shape. pxx's static `shr` is a 64-bit LOGICAL shift on Integer and on Int64
  alike; its Variant `shr` was ARITHMETIC, because that arm was written for
  NilPy (Python's `>>` sign-extends) and Pascal reached the same emitter.
  `v(-12) shr 1` answered -6 where `Int64(-12) shr 1` answers
  9223372036854775802 -- two different operators under one spelling inside one
  language, which is the disagreement that matters. FPC is a THIRD answer
  (2147483642: it narrows a Variant to 32 bits first) and we deliberately do
  not copy that narrowing -- decide-variant-bitwise-width, decided 2026-08-25,
  option 2. So the negative rows below assert VARIANT-EQUALS-STATIC, computing
  the want from the static operator rather than hard-coding a constant: that is
  the property being claimed, and it is the one an FPC oracle cannot express.
  bug-a-variant-shr-is-arithmetic-where-static-shr-is-logical }
uses variants;
var
  a, b, c: Variant;
  l: Int64;
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

  { A NEGATIVE operand under every bitwise operator, each row asserting that the
    Variant answers what the SAME operator answers on a static Int64. The want
    is COMPUTED from the static operator on purpose -- a hard-coded constant
    would still pass if both sides drifted together, and drifting together is
    not the property. Both operand shapes are covered: a Variant right-hand
    side and a plain integer literal, because the literal boxes through a
    different path.

    The Variant is loaded from a LITERAL, not from `l`, on purpose: assigning
    an Int64 VARIABLE to a Variant truncates to 32 bits on i386 and arm32 --
    their backends move four bytes into the 8-byte payload and zero the rest,
    so `a := l` with l = -12 makes a Variant holding 4294967284 and every row
    below then answers correctly for the WRONG operand. That is the fat-slot
    model's own gap, filed as
    bug-a-an-int64-assigned-to-a-variant-truncates-to-32-bits-on-i386-and-arm32,
    and it is not what these rows are about. A literal boxes correctly on all
    four targets. }
  l := -12;
  a := -12; b := 1;
  ChkI('agree shr var', a shr b, l shr 1);
  ChkI('agree shr lit', a shr 1, l shr 1);
  ChkI('agree shl var', a shl b, l shl 1);
  ChkI('agree or',      a or 5,  l or 5);
  ChkI('agree xor',     a xor 5, l xor 5);
  ChkI('agree and',     a and 5, l and 5);

  { A result WIDER than 32 bits. The payload of an integer Variant is a full
    Int64 on every target, but the runtime renderer read it back through a
    MACHINE word -- four bytes on i386 and arm32 -- so `v(1) shl 40` wrote 0
    and `v(3000000000) * 2` wrote 1705032704 there while x86-64 and aarch64,
    where a machine word happens to be eight bytes, printed both correctly.
    Measured 2026-08-26 on x86-64, i386, arm32 and aarch64: all four now agree
    with the static row below. }
  l := 1;
  a := 1; b := 40;
  ChkI('wide shl', a shl b, l shl 40);

  if fails = 0 then writeln('ALL OK') else writeln(fails, ' FAILURES');
end.
