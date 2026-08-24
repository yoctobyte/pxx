{ An element of an `array of ^PChar`, dereferenced, in every context that has to
  recognise a PChar.

  This is the shape the PChar/WideChar-conversion ticket recorded as its last
  open one, with the diagnosis "unlike the residual it replaces, this one really
  is missing metadata ... there is no SymElemPtrDepth". That diagnosis was wrong,
  and the way it was wrong is why this test exists: an array symbol is not itself
  a pointer, so AllocArray parks the ELEMENT's depth and ultimate base in the
  symbol's own SymPtrDepth/SymPtrBaseTk slots. The metadata was there; the deref
  chain's AN_INDEX arm read the immediate pointee and never the pair beside it.

  Note the SPREAD, which is the part a single-context test would have missed.
  Three contexts looked correct before the fix -- `AnsiString(x)`, `s := x` and
  `Length(AnsiString(x))` -- not because the shape was recognised but because
  `AnsiString(<any pointer>)` treats its operand as a PChar unconditionally.
  WriteLn, concat and the two comparisons are the contexts that correctly refuse
  to guess, and all four were wrong. "Half the contexts work" is what an
  unrecognised shape looks like when a blanket rule covers the other half.

  Every row below is byte-identical to fpc 3.2.2 on this source. `pinned` gets
  four of them wrong.
  refactor-centralize-managed-string-pchar-conversion }
program test_pchar_array_of_pointer_to_pchar;
{$mode objfpc}{$H+}
type PPC = ^PChar;
var
  base: array[0..1] of AnsiString;
  p0, p1: PChar;
  qa: array[0..1] of PPC;
  qd: array of PPC;
  s: AnsiString;
begin
  base[0] := 'alpha'; base[1] := 'beta';
  p0 := PChar(base[0]); p1 := PChar(base[1]);
  qa[0] := @p0; qa[1] := @p1;
  SetLength(qd, 2); qd[0] := @p0; qd[1] := @p1;

  WriteLn(qa[0]^);                       { was: the address, in decimal }
  WriteLn(qa[1]^);
  s := qa[0]^;            WriteLn(s);    { right before, by the blanket cast rule }
  WriteLn('x' + qa[1]^);                 { was: empty }
  WriteLn(qa[0]^ + 'y');                 { was: the address, then 'y' }
  WriteLn(AnsiString(qa[0]^));           { right before }
  WriteLn(Length(AnsiString(qa[1]^)));   { right before }
  WriteLn(qa[0]^ = 'alpha');             { was: FALSE -- compared POINTERS }
  WriteLn(qa[1]^ <> 'alpha');            { was: TRUE for the wrong reason }

  { ...and the same element shape over a DYNAMIC array, which reaches the same
    arm through a different allocator (AllocDynArray, not AllocArray). }
  WriteLn(qd[0]^);
  WriteLn('x' + qd[1]^);
  WriteLn(qd[0]^ = 'alpha');
end.
