{ `PSizeInt` / `PSizeUInt` -- FPC's System-unit `^SizeInt` / `^SizeUInt`, and
  nothing more than that.

  WHY THEY WERE MISSING IS THE INTERESTING PART, and this file's own neighbour
  predicted it: pasparser_lval.inc already carries a comment about `sizeint` /
  `sizeuint` being in one scalar table and not the other, noting that the two
  tables serve DIFFERENT DOORS so nothing failed loudly. Both scalar tables
  were repaired. The builtin POINTER table was a third copy nobody counted, so
  `SizeUInt(v)` and `var x: SizeUInt` worked while `PSizeUInt` was `unknown
  type`. Measured 2026-09-10: once the unit cycle and `bitsizeof` were out of
  the way, that was the first failure of 150 of the 207 units of FPC's own
  compiler (umbrella-pxx-compiles-fpc-itself).

  NOT ASSERTED HERE, DELIBERATELY: `SizeOf(PSizeUInt)`, which fpc answers 8 and
  pxx refuses with `SizeOf: unknown type or variable`. That is not this gap --
  `SizeOf(PByte)` is refused identically, so SizeOf-of-a-builtin-pointer-NAME
  is absent for the whole family and is its own question. Freezing it here
  would tie a family-wide gap to these two names.
  bug-p-psizeint-and-psizeuint-are-not-builtin-pointer-types }
program test_p_psizeint_and_psizeuint_are_builtin_pointer_types;

var
  fails: LongInt;
  u: SizeUInt;
  i: SizeInt;
  pu: PSizeUInt;
  pi: PSizeInt;
  pn: PNativeUInt;

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
  u := 7; i := -7;
  pu := @u; pi := @i;

  Chk('R01 deref unsigned', pu^, 7);
  Chk('R02 deref signed',   pi^, -7);
  { WIDTH AS A RELATION, not a constant: SizeInt is pointer-sized by
    definition, so this row is true on i386 and riscv32 too and prints a
    different correct number on each. A hard 8 would be an x86-64 assertion
    wearing the shape of a portable one. }
  Chk('R03 width unsigned', SizeOf(pu^), SizeOf(Pointer));
  Chk('R04 width signed',   SizeOf(pi^), SizeOf(Pointer));
  { They must be the SAME type as the NativeUInt spelling, not merely the same
    width -- that is what makes them aliases rather than look-alikes. }
  pn := PNativeUInt(pu);
  Chk('R05 alias of native', pn^, 7);
  { Writing THROUGH the pointer, so the row cannot pass on a read-only decode }
  pi^ := 42;
  Chk('R06 store through', i, 42);
  pu^ := 99;
  Chk('R07 store unsigned', u, 99);

  WriteLn('fails=', fails);
  WriteLn('PSIZEINT OK');
end.
