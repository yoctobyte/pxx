program test_string_to_pointer_seam_leaks;
{ Every seam where a managed string becomes a RAW POINTER gives it an owner.

  A pointer destination retains nothing -- a PChar/Pointer parameter keeps an
  address, a pointer-typed variable stores a bare handle, a pointer CAST is a
  tag change. So a managed string that arrives at one of them carrying a +1
  nobody holds can never be released: no scope-exit scan can see it, because it
  was never a symbol. All three spellings leaked with frees=0.

  live before -> after, one arm per program, 1000 trips each, against the
  binary immediately before the fix:
    Cish('lit' + c)            Cish(s: PChar) cdecl, IMPLICIT   921 -> 3
    p := 'lit' + c             p: PChar                         921 -> 3
    Pointer('lit' + c + 'x')   the generic pointer cast         921 -> 4

  The first two keep allocs at 921 -- same traffic, so the delta is ownership.
  THE THIRD DOES NOT, and the reason is worth the line: it goes 921 -> 1871,
  which is the SAME traffic the named-intermediate spelling
  (`t := 'lit' + c + 'x'; q := Pointer(t)`) reads at 1871/1869. The pre-fix
  number was low because the unowned value let a concat be dropped, so 1871 is
  the honest count and 921 was a second symptom rather than a baseline.

  This whole program, against fa002ef63d15 (the binary immediately before the
  fix): live 3138 -> 6 against a bound of 50, allocs 4274 -> 4809 for the reason
  just given. REJECTED by the pre-fix binary (rc=1), which is the check that
  says it can fail at all. Identical on all five targets.

  The implicit arm is the one that matters in real code: no PChar() appears in
  the source at all. It is the conversion every C binding relies on, and it was
  reached through IRLowerCallArg -- the single funnel every call argument
  passes -- because the seven managed-string-temp sites ask
  ParamWantsManagedStrTemp, which is False for a pointer parameter by
  construction.

  NO FPC ORACLE ROW, and that is a fact about the spellings rather than an
  omission. FPC REJECTS the implicit conversion outright -- `Cish('lit' + c)`
  is "Incompatible type for arg no. 1: Got AnsiString, expected PChar" and
  `p := 'lit' + c` is "Incompatible types: got AnsiString expected PChar". Only
  the `Pointer(...)` cast arm compiles there. pxx accepts all three deliberately
  (it is what lets a C binding take a Pascal string without PChar() boilerplate)
  and accepting what FPC rejects is not a defect -- but it does mean the
  ownership rule for these spellings is ours to define, and dropping the +1 was
  still wrong. So this test is checked against itself and against the absolute
  bound, not against the oracle.

  The printed lines cannot catch any of this: the pre-fix binary printed all of
  them identically while leaking. They are aimed at the OPPOSITE mistake, a temp
  released too early, which would corrupt the readback rather than move a count.
  bug-a-a-managed-string-reaching-a-pointer-destination-has-no-owner }
{$mode objfpc}{$H+}
uses sysutils;

const N = 1000;

var i, sink: Integer;
    c: Char;
    t, acc: AnsiString;
    p: PChar;
    q: Pointer;

function Cish(s: PChar): PtrInt; cdecl;
begin
  Cish := Ord(s^);
end;

begin
  sink := 0; acc := ''; t := '';

  { IMPLICIT AnsiString -> PChar parameter, no cast in the source }
  for i := 1 to N do
  begin
    c := Chr(48 + i mod 10);
    Inc(sink, Cish('lit' + c));
  end;

  { assignment to a PChar variable }
  for i := 1 to N do
  begin
    c := Chr(48 + i mod 10);
    p := 'lit' + c;
    Inc(sink, Ord(p^));
  end;

  { the generic pointer cast }
  for i := 1 to N do
  begin
    c := Chr(48 + i mod 10);
    q := Pointer('lit' + c + 'x');
    if q <> nil then Inc(sink);
  end;

  { CONTROL: named locals, which already owned their strings }
  for i := 1 to N do
  begin
    c := Chr(48 + i mod 10);
    t := 'lit' + c;
    p := PChar(t);
    Inc(sink, Cish(p) + Ord(p^));
  end;

  { the pointers are READ, so a temp released too early shows up as wrong
    output rather than as a leak count }
  for i := 1 to 200 do
  begin
    p := 'row' + IntToStr(i mod 9);
    acc := acc + Char(p[3]);
    Inc(sink, Ord(p[0]) + Ord(p[3]));
  end;

  WriteLn('sink=', sink);
  WriteLn('acclen=', Length(acc), ' head=', Copy(acc, 1, 9));
end.
