program pinned_rtl_consumer_probe;
{ The CONSUMER half of gate.sh's `pinned builds live lib/rtl` row. The sweep
  compiles lib/rtl's own units, so a name MOVED out of lib/rtl into
  compiler/builtin is invisible to it: no lib/rtl unit uses the name, and the
  breakage lands in code outside lib/rtl (0ffe185bb broke
  external/synapse/synautil.pas that way with the sweep honestly GREEN).
  This program is outside lib/rtl, names no unit, and uses the moved names as
  a consumer would. When you move a name from lib/rtl into compiler/builtin,
  add a use of it here.
  bug-a-the-pinned-compiler-cannot-build-live-lib-rtl-and-nothing-tracks-it }
{$mode objfpc}
var s: AnsiString; p: Pointer; a: array of Integer; w: UnicodeString;
begin
  SetString(s, PChar('abcdef'), 3);
  p := AllocMem(16);
  SetLength(a, 5);
  w := UTF8Decode('h');
  WriteLn(s, ' ', PByte(p)^, ' ', DynArraySize(Pointer(a)), ' ',
          UTF8Encode(w), ' ', Length(sLineBreak));
  FreeMem(p);
end.
