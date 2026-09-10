{ `Unaligned(x)` IS `x`, on BOTH sides of `:=`.

  FPC's in_unaligned_x (compinnr.pas:77) yields its argument unchanged and only
  relaxes the compiler's alignment assumption about the access. It is not a
  function, and that is the whole point of this test: a function's result is not
  assignable, and FPC's own compiler assigns through it --
  `unaligned(pqword(@floatx80_ba[2])^) := floatx80_e.low` (entfile.pas:2003),
  plus ogomf.pas and owomflib.pas. cclasses.pas only READS through it, and
  cclasses is what 150 of FPC's 207 compiler units stop on, so an implementation
  shaped like an ordinary builtin clears 150 units and leaves those three
  failing on the identical spelling. Both halves are asserted here for that
  reason: R01-R03 need the read arm (pasparser_expr.inc), R04-R06 need the write
  arm (pasparser_stmt.inc), and reverting EITHER makes this file fail to
  COMPILE. Verified in both directions, not assumed -- the two arms are separate
  code paths and neither makes the other's rows pass.

  WHY IDENTITY IS EXACT HERE AND NOT A COMPROMISE: pxx carries no alignment on
  a load or a store at all -- IR_LOAD_MEM and IR_STORE_MEM have no such flag --
  so `p^` is one plain access on every target already. This says out loud what
  every other dereference was doing. Whether a strict-alignment target should
  split a possibly-unaligned access into bytes is a real question, and it is a
  question about `p^`; it was open before this intrinsic existed and is
  untouched by it.

  Every pointer here is deliberately offset by ONE byte from the array base, so
  the accesses really are unaligned rather than nominally so. Values come from
  fpc 3.2.2 on the same source.
  umbrella-pxx-compiles-fpc-itself }
program test_p_unaligned_is_a_transparent_lvalue;

var
  fails: LongInt;
  buf: array[0..15] of Byte;
  p: PByte;
  i: LongInt;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got = want then
    WriteLn(what, ' ok')
  else
  begin
    WriteLn(what, ' FAIL got=', got, ' want=', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  for i := 0 to 15 do buf[i] := i;
  p := @buf[1];   { one byte off, so these are genuinely unaligned accesses }

  { ---- read half ---- }
  Chk('R01 read dword', unaligned(PLongWord(p)^), $04030201);
  Chk('R02 read word',  unaligned(PWord(p)^), $0201);
  { the identity claim stated directly, rather than inferred from R01 }
  Chk('R03 read = bare deref',
      Int64(unaligned(PLongWord(p)^)) - Int64(PLongWord(p)^), 0);

  { ---- write half: this is the arm a function cannot provide ---- }
  unaligned(PLongWord(p)^) := $11223344;
  Chk('R04 write dword', PLongWord(p)^, $11223344);
  { the store landed at the UNALIGNED address and nowhere else }
  Chk('R05 byte below untouched', buf[0], 0);
  Chk('R06 first stored byte', buf[1], $44);

  WriteLn('fails=', fails);
  WriteLn('UNALIGNED OK');
end.
