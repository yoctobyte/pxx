{ Six names FPC keeps in its System unit, called from a program with NO `uses`
  clause at all.

  THE ABSENT `uses` LINE IS THE ENTIRE TEST. Any `uses` clause pulls the builtin
  unit (the tkUses arm of the pre-scan), so adding one -- even `uses SysUtils`,
  even `uses Math` -- makes every row below pass whatever the declarations say,
  and the fixture stops being able to fail. Do not add one.

  These lived in lib/rtl/sysutils.pas only, so an FPC program that compiles
  unchanged everywhere else answered `undefined variable (DynArraySize)` here
  and one `uses sysutils` line fixed it. That is the second sign of the
  unit-boundary class whose FIRST sign -- a sysutils declaration SHADOWING
  dynamic-array Delete/Insert -- was fixed at f5ad23c32 / 475528dae. Opposite
  directions, same root, same tell: one `uses` line changing the answer.

  MEASURED IN TWO HALVES, and the second is what turns a census into a defect
  list. tools/rtl_unit_boundary_census.py named twelve candidates; a per-name
  probe then compiled a no-uses program against fpc 3.2.2 and against pxx for
  each of them, and eleven were real. Six moved here; the other five are held
  back for a reason that is about the PIN and not about the names -- see the
  note in compiler/builtin/builtin.pas.

  SINCE 2026-09-11 THE SIX ARE DECLARED IN lib/rtl/sysutils.pas AS WELL, and
  this fixture is deliberately unaffected by that: with no `uses` line it cannot
  see sysutils at all, so every row below still tests exactly one thing --
  builtin's copy. The duplicate spans one pin-era (a $(PXX_STABLE) build reads a
  FROZEN builtin that predates the move, and external/synapse and fpjson went
  red for two days on it) and carries its own retirement test; see the note on
  sLineBreak in lib/rtl/sysutils.pas.

  `alloc 0` IS NOT A SMOKE ROW. AllocMem differs from GetMem only in zeroing, so
  a GetMem alias compiles everywhere, passes any "did it return a pointer" test,
  and crashes later on a pointer field read out of garbage. Reading the first
  byte is the one assertion that separates them.

  Expected output is fpc 3.2.2's for this exact source.
  task-b-nineteen-sysutils-names-that-fpc-keeps-in-system }
program test_b_system_names_reach_a_program_with_no_uses_clause;
{$mode objfpc}{$H+}
var
  p: Pointer;
  a: array of LongInt;
  s: AnsiString;
  c: array[0..3] of Char;
  w: UnicodeString;
begin
  p := AllocMem(16);
  WriteLn('alloc   ', PByte(p)^);
  FreeMem(p);

  SetLength(a, 5);
  WriteLn('dynsize ', DynArraySize(Pointer(a)));
  WriteLn('dynnil  ', DynArraySize(nil));

  c[0] := 'a'; c[1] := 'b'; c[2] := 'c'; c[3] := #0;
  SetString(s, @c[0], 3);
  WriteLn('setstr  ', s, '|', Length(s));
  SetString(s, @c[0], 0);
  WriteLn('setstr0 ', '<', s, '>|', Length(s));

  WriteLn('linebrk ', Length(sLineBreak));

  w := UTF8Decode('abc');
  WriteLn('utf8dec ', Length(w));
  WriteLn('utf8enc ', UTF8Encode(w));
end.
