{ A pointer cast of an ALREADY-OWNED string must not retain it.

  IRParkManagedStr gives an unowned managed value an owner, and it used to park
  UNCONDITIONALLY on the reasoning that IR_STORE_SYM "MOVES a fresh call result
  and RETAINS anything else, so an already-owned value gains a balanced
  retain/release rather than a second free". Safe, and the word BALANCED was
  wrong: the release lands at the ENCLOSING SCOPE's exit, and the main program
  body's scope exit is PROGRAM exit. So each `Pointer(s)` SITE in the main body
  added +1 that was never given back while main ran.

  Bounded, not a use-after-free: +1 per site, not per iteration, payload intact.
  But an owned string that cannot be freed for the life of the program, and
  every refcount assertion in the corpus reading one too many — which is how it
  was found, because test_threadsafe_refcount_lockfree reads the count THROUGH
  the very cast that was doing the retaining.

  FPC 3.2.2 holds this at 1 for every row below. Measured, not reasoned:
  pxx read 2/3/4/5 before the fix and 1/1/1/1 after, matching FPC exactly.

  THE PARK MUST STILL HAPPEN where the value is unowned — that direction is
  covered by test_string_to_pointer_seam_leaks, test_pchar_of_computed_string_
  leaks and test_array_of_const_string_leaks, which all still bound at 50.
  bug-a-pointer-cast-of-an-owned-string-retains-it-for-the-rest-of-the-program }
program test_pointer_cast_owned_string_refcount;
{$mode objfpc}{$H+}
var s: AnsiString; p: Pointer; pc: PChar; k, bad: Integer;
{ machine-word alias, declared here on purpose: the refcount at [handle-16] is
  eight bytes and `PWord` is two (it only read eight while builtinheap's leaked
  alias shadowed the builtin one). }
type PRefCnt = ^NativeInt;
function Cnt: Int64; begin Cnt := PRefCnt(Int64(PChar(s)) - 16)^; end;
procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin WriteLn('FAIL ', what, ' = ', got, ' want ', want); Inc(bad); end
  else WriteLn('ok   ', what, ' = ', got);
end;
begin
  bad := 0;
  s := '';
  for k := 1 to 44 do s := s + Chr(65 + (k mod 26));

  Chk('after build', Cnt, 1);
  p := Pointer(s);   Chk('after Pointer(s) #1', Cnt, 1);
  p := Pointer(s);   Chk('after Pointer(s) #2', Cnt, 1);
  p := Pointer(s);   Chk('after Pointer(s) #3', Cnt, 1);
  pc := PChar(s);    Chk('after PChar(s)', Cnt, 1);

  { per SITE, not per iteration — a loop over one site must not move it either }
  for k := 1 to 5000 do p := Pointer(s);
  Chk('after 5000 trips through one site', Cnt, 1);

  { the payload must survive all of it }
  if Copy(s, 1, 8) <> 'BCDEFGHI' then
  begin WriteLn('FAIL payload = ', Copy(s, 1, 8), ' want BCDEFGHI'); Inc(bad); end
  else WriteLn('ok   payload intact');

  if (p = nil) or (pc = nil) then WriteLn('unreachable');
  if bad = 0 then WriteLn('POINTERCASTRC OK') else WriteLn('POINTERCASTRC FAILED fail=', bad);
  if bad <> 0 then Halt(1);
end.
