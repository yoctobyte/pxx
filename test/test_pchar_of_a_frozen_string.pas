{ PChar OF A FROZEN STRING, EVERY SPELLING, AT THE OPERAND'S OWN PREFIX WIDTH.

  A frozen string's value points at its LENGTH PREFIX; PChar must land on the
  first character, i.e. at prefix+0. The prefix is 8 bytes for tyString/
  tyFixedString and ONE byte for tyShortString (-dPXX_SHORTSTRING), so a
  hardcoded +8 puts the pointer seven bytes into the NUL-padded tail and the
  callee sees an EMPTY string -- the quietest possible failure, on the path
  every C binding takes. See
  bug-a-pchar-of-a-frozen-string-skips-8-bytes-whatever-the-prefix-width-is.

  NO EXPECTED VALUE IN THIS FILE NAMES A WIDTH. Every offset row asserts the
  RELATION `PChar(x) - @x = SizeOf(TS) - 8` (capacity is 8 chars, so what is
  left is the prefix), which is true in both modes and on all seven targets
  while printing a different correct number on each. A row expecting a literal
  8 would pass in the default mode for the same reason the bug survived there.

  FPC IS NOT AN ORACLE FOR THIS FILE. FPC 3.2.2 rejects every frozen spelling
  here -- `Illegal type conversion: "TS" to "PChar"` for the casts and
  `Incompatible type for arg no. 2: Got "TS", expected "Pointer"` for the
  implicit passes. Accepting what FPC rejects is not a defect (CLAUDE.md), but
  it does mean the expected output is pxx's own and cannot be diffed against
  the oracle. Do not "fix" a row here by consulting FPC.

  THREE SPELLINGS AND ONLY TWO ARMS. `f(PChar(x))` is rescued by the AN_CALL
  prefix-skip arm whenever the cast arm declined to fire, which is why the
  record-field row read correct through a call while `q := PChar(r.f)` -- same
  cast, no call to rescue it -- pointed at the length byte. The assignment rows
  below exist because a call-argument probe cannot see that. }
program test_pchar_of_a_frozen_string;
type
  TS = string[8];
  TR = record f: TS; end;
var
  s: TS; arr: array[0..1] of TS; r: TR; p: ^TS; m: AnsiString; q: Pointer;

function Walk(x: Pointer): AnsiString;
var c: ^Char; i: Integer;
begin
  Walk := ''; c := x; i := 0;
  while (i < 16) and (c^ <> #0) do
  begin Walk := Walk + c^; c := Pointer(PtrUInt(c) + 1); Inc(i); end;
end;

procedure Row(tag: AnsiString; got: AnsiString);
begin
  WriteLn(tag, ' [', got, '] ', got = 'abcde');
end;

procedure Implicit(tag: AnsiString; x: Pointer);
begin
  Row(tag, Walk(x));
end;

{ THE WIDTH ITSELF IS DELIBERATELY NOT IN THE COMPARED OUTPUT. It is 8 in the
  default mode and 1 under -dPXX_SHORTSTRING -- both correct -- so printing it
  would need two .expected files and would bake a per-mode constant into a file
  whose whole point is that the constant is not the claim. The RELATION is the
  claim, and it cannot pass vacuously: if the skip disappeared the left side
  would be 0 and the right side is never 0. }
procedure Off(tag: AnsiString; pc, base: Pointer);
begin
  WriteLn(tag, ' isprefix=', PtrUInt(pc) - PtrUInt(base) = PtrUInt(SizeOf(TS)) - 8);
end;

begin
  s := 'abcde'; arr[0] := 'abcde'; arr[1] := 'zz'; r.f := 'abcde';
  p := @s; m := 'abcde';

  { 1. explicit PChar cast, as a call argument }
  Row('cast var ', Walk(PChar(s)));
  Row('cast elem', Walk(PChar(arr[0])));
  Row('cast fld ', Walk(PChar(r.f)));
  Row('cast drf ', Walk(PChar(p^)));
  Row('cast lit ', Walk(PChar('abcde')));
  Row('cast ansi', Walk(PChar(m)));

  { 2. implicit pass of the string itself to a Pointer parameter }
  Implicit('imp  var ', s);
  Implicit('imp  elem', arr[0]);
  Implicit('imp  fld ', r.f);
  Implicit('imp  lit ', 'abcde');
  Implicit('imp  ansi', m);

  { 3. THE SPELLING WITH NO CALL TO RESCUE IT: the cast's own result, stored }
  q := PChar(s);      Row('asg  var ', Walk(q));
  q := PChar(arr[0]); Row('asg  elem', Walk(q));
  q := PChar(r.f);    Row('asg  fld ', Walk(q));
  q := PChar(p^);     Row('asg  drf ', Walk(q));

  { 4. the offset IS the prefix width, whatever that width is here }
  Off('off  var ', PChar(s), @s);
  Off('off  elem', PChar(arr[0]), @arr[0]);
  Off('off  fld ', PChar(r.f), @r.f);
  Off('off  drf ', PChar(p^), p);

  { 5. POSITIVE CONTROL, drawn from the population the arm must NOT touch: a
       cast of a plain POINTER stays a pure reinterpret and adds nothing. If
       the frozen guard ever widens to "anything castable", this row moves. }
  q := @s;
  WriteLn('ctl  ptr  adds0=', PtrUInt(PChar(q)) = PtrUInt(@s));

  { 6. MUST-DIFFER partner: element 1 holds different bytes, so no row above can
       be passing by reading element 0 or a shared constant. }
  WriteLn('ctl  elem1 [', Walk(PChar(arr[1])), '] ', Walk(PChar(arr[1])) = 'zz');
end.
