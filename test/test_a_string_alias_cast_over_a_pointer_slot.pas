program test_a_string_alias_cast_over_a_pointer_slot;
{ `type t = AnsiString; t(x)` means two different things depending on what x IS,
  and the arm that built it read the ALIAS's kind, which is a string either way.
  Over a string it is a value-level no-op; over a POINTER slot it is a real
  reinterpret. uPSCompiler.pas stores every string that way, 93 times.

  ROWS D..H ARE CONTROLS AND WERE ALL GREEN BEFORE THE FIX -- the no-op over a
  string literal, over a string variable, through a `^AnsiString` deref, through
  a record field, and the built-in spelling. They are what say the fix is a
  ROUTE and not a new behaviour: `AnsiString(p)` and `String(p)` have always
  done the right thing, and the alias spelling now reaches the same node.

  ROW E IS THE ONE THAT FAILS IF THE DISCRIMINATOR IS WRITTEN AS "not a string"
  RATHER THAN "is a pointer". The one-character literal ' ' arrives tagged
  tyChar, so a negative test sweeps it into the reinterpret and Pos answers
  nothing -- measured, not predicted. A char operand is a CONVERSION.

  ROW C IS THE DEFECT THE TICKET DID NOT HAVE. It reported the store as already
  correct, which is true for a string VARIABLE source (`t(p) := s` writes the
  live payload pointer, so `p = Pointer(s)`) and false for a LITERAL. Nothing at
  the call site distinguishes them.

  NOT COVERED HERE, DELIBERATELY: `SetLength(t(p), n)`. It fails identically
  through the BUILT-IN spelling, so it is not an alias defect at all --
  bug-p-setlength-over-a-string-cast-of-a-pointer-slot-has-no-lowering.
  bug-p-a-string-alias-cast-over-a-pointer-slot-is-a-no-op-and-reads-the-pointer }
{$mode delphi}
type
  t  = AnsiString;
  TR = record f: AnsiString; end;
var
  p, q: Pointer;
  s: AnsiString;
  ps: ^AnsiString;
  r: TR;
begin
  s := 'abc';

  t(p) := s;                                     { store a VARIABLE through the alias }
  WriteLn('A: ', t(p));
  WriteLn('B: ', Length(t(p)));

  t(q) := 'abc';                                 { store a LITERAL through the alias }
  WriteLn('C: ', Length(t(q)), ' ', t(q));

  WriteLn('D: ', t('hello'));                    { operand already a string literal }
  WriteLn('E: ', Pos(t(' '), 'a b'));            { one-char literal: a CONVERSION }

  ps := @s;
  WriteLn('F: ', Length(t(ps^)));                { operand a ^AnsiString deref }

  r.f := 'wxyz';
  WriteLn('G: ', Length(t(r.f)));                { operand a record field }

  WriteLn('H: ', Length(AnsiString(p)), ' ', AnsiString(p));   { the built-in spelling }
end.
