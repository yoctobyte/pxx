unit uambientsys;
{ A unit that calls the elementary math functions with NO `uses` clause at all
  — FPC declares sqrt/ln/exp/sin/cos/arctan/pi in the System unit, so this is
  the portable spelling and FPC's own compiler sources use it. pxx keeps them
  in the `math` unit and pulls it in ambiently, the same way `textfile` is
  pulled for Text/Assign.
  bug-p-the-system-math-and-thread-surfaces-are-not-ambient-in-units

  ...and, 2026-09-09, THE SAME CLASS A THIRD TIME, which is why these live in
  this unit rather than a new one. FPC also keeps AllocMem / DynArraySize /
  SetString / sLineBreak / UTF8Decode / UTF8Encode in System; pxx had them in
  lib/rtl/sysutils only, so a program with no `uses` line could not reach them
  at all AND a unit could not either -- two separate holes, because the
  program-level ambient scan reads only the PROGRAM's tokens. The routines
  below are the UNIT half; the program half is asserted by the caller, which
  names none of them.
  task-b-nineteen-sysutils-names-that-fpc-keeps-in-system }
interface

function Hypot2(a, b: Double): Double;
function LogSum(x: Double): Double;
function Circle(r: Double): Double;

{ Each of these calls exactly one System-side name with no `uses` clause. }
function SysAlloc: Integer;
function SysDynLen: Integer;
function SysSetStr: AnsiString;
function SysLineBreakLen: Integer;
function SysUtf8Round(const a: AnsiString): AnsiString;

implementation

function Hypot2(a, b: Double): Double;
begin
  Hypot2 := sqrt(a * a + b * b);
end;

function LogSum(x: Double): Double;
begin
  LogSum := ln(x) + exp(0.0) + sin(0.0) + cos(0.0) + arctan(0.0);
end;

function Circle(r: Double): Double;
begin
  Circle := pi * r * r;
end;

function SysAlloc: Integer;
var p: Pointer;
begin
  { AllocMem ZEROES, which is the whole difference from GetMem -- reading the
    first byte is what makes this row fail if it were aliased to GetMem. }
  p := AllocMem(16);
  SysAlloc := PByte(p)^;
  FreeMem(p);
end;

function SysDynLen: Integer;
var a: array of LongInt;
begin
  SetLength(a, 5);
  SysDynLen := DynArraySize(Pointer(a));
end;

function SysSetStr: AnsiString;
var s: AnsiString; c: array[0..3] of Char;
begin
  c[0] := 'a'; c[1] := 'b'; c[2] := 'c'; c[3] := #0;
  SetString(s, @c[0], 3);
  SysSetStr := s;
end;

function SysLineBreakLen: Integer;
begin
  SysLineBreakLen := Length(sLineBreak);
end;

function SysUtf8Round(const a: AnsiString): AnsiString;
begin
  SysUtf8Round := UTF8Encode(UTF8Decode(a));
end;

end.
