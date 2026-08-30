{ ParamStr(i) in EXPRESSION position, with an argument longer than the frozen
  temp that position desugars to.

  `ParamStr(i)` as an expression becomes ArgStr(i, <hidden frozen temp>), and a
  frozen string slot is LOCAL_STR_CAP+8 = 264 bytes. The x86-64 fill copied a
  full unbounded strlen(argv[i]) with `rep movsb`, so a longer argument wrote
  straight past the slot into the neighbouring frame slot -- in the report, the
  enclosing loop's own counter and bound, which turned `for i := 1 to ParamCount`
  into 1.29 MILLION iterations before it was killed. It also stored a length
  larger than the capacity, so Length() answered 300 for a 256-byte buffer.

  255, not 256, and that is not an arbitrary pick: it is what FPC answers for
  this exact program (ParamStr returns a ShortString), and what riscv32 and
  xtensa already produced via PXXCStrToFrozen. So the clamp buys FPC parity and
  cross-target agreement at once -- clamping at LOCAL_STR_CAP would have made a
  256-byte argv entry render differently per target and differently from FPC.

  The managed row is the other half of the contract and must stay 300: passing a
  real `string` destination goes through EmitArgvToStringManaged, which sizes the
  allocation from the length, and is the full-length escape hatch. If that row
  ever reads 255 the clamp has leaked into the path that must not have one.

  bug-a-x86-64-paramstr-expression-smashes-its-frozen-temp }
program test_paramstr_long_arg;
var i: Integer; s: string;
begin
  WriteLn('count=', ParamCount);
  { the loop is itself part of the assertion: its counter and bound are what the
    overflow used to smash, so reaching `done` at all is the regression check }
  for i := 1 to ParamCount do
    WriteLn('expr[', i, ']len=', Length(ParamStr(i)));
  i := 2;
  ArgStr(i, s);
  WriteLn('managed=', Length(s));
  WriteLn('done');
end.
