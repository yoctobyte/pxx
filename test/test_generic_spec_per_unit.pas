program test_generic_spec_per_unit;
{ Two units that each write the SAME specialization of the SAME template under
  the SAME alias name, without using each other.

  The Specializations[] table is one flat global list, but a specialization is
  not a global fact: SpecializeStream declares an ordinary class under the
  alias name in whatever unit is being parsed, and that declaration obeys the
  same one-hop `uses` rule as any other type. The "already declared, no-op"
  shortcut asked the flat table and skipped the second unit's declaration
  entirely — so the very next line, `var lt: TLongIntTest;`, failed with
  `unknown type: TLongIntTest` in a unit whose own source declares it
  (FPC test suite tgeneric96).

  The units also carry tgeneric96's other half: a generic `TTest<>` and a
  NON-generic `TTest` in scope at once, pulled in in OPPOSITE ORDERS by the
  two units. `specialize TTest<LongInt>` must reach the template and a bare
  `TTest` must reach the class, whichever came last in the uses clause.

  Expected values are FPC 3.2.2's. }

uses
  ugspeca,
  ugspecb;

var
  a: ugspeca.TLongIntTest;
  b: ugspecb.TLongIntTest;
  ok, tot: Integer;

procedure Check(const nm: string; got, want: Integer);
begin
  tot := tot + 1;
  if got = want then begin ok := ok + 1; writeln('ok   ', nm); end
  else writeln('FAIL ', nm, ' = ', got, ' want ', want);
end;

begin
  ok := 0; tot := 0;
  a := MakeA;
  b := MakeB;
  Check('unit a specialization', a.Val, 11);
  Check('unit b specialization', b.Val, 22);
  { the non-generic homonym, reached from both uses orders }
  Check('unit a plain TTest', PlainA.Tag, 7);
  Check('unit b plain TTest', PlainB.Tag, 7);
  writeln('total ok ', ok, ' / ', tot);
end.
