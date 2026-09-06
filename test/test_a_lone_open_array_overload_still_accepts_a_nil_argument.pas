program test_a_lone_open_array_overload_still_accepts_a_nil_argument;
{ The preserved-laxness half of
  bug-p-an-open-array-and-a-named-dynamic-array-parameter-are-one-signature.

  That fix makes a named dynamic array BEAT an open array for a literal nil.
  The direction it must NOT drift in is refusing nil at an open array
  altogether -- which is what fpc 3.2.2 does, and which would read like the
  tidier rule:

      Incompatible type for arg no. 1: Got "Pointer", expected {an open
      array of LongInt, spelled by fpc with a brace-wrapped Open}

  Us accepting what fpc rejects is not a defect (CLAUDE.md), so pxx keeps
  binding it, and the new phase only ever REORDERS candidates -- it never
  grants one and never withdraws one. This program is the assertion of that:
  a LONE open-array candidate, with no dynamic-array sibling for the phase to
  prefer, still takes nil and still sees an empty array.

  IT CANNOT LIVE IN THE SIBLING FIXTURE, which is cross-checked against fpc
  line for line. fpc will not compile this program at all, so a row here is
  not an fpc-differential row and must not be read as one. That is the reason
  for a second file rather than a seventh row.

  Low(a) is 0 and High(a) is -1 for an empty open array; both are asserted,
  because a binding that passed the pointer's own bytes rather than an empty
  array would still have a Length of 0 in the shape that used to fail. }

var
  fails: Integer;

procedure Check(const what: AnsiString; g, w: Integer);
begin
  if g <> w then
  begin
    WriteLn('FAIL ', what, ': got ', g, ' want ', w);
    fails := fails + 1;
  end;
end;

var
  seenLen, seenLow, seenHigh: Integer;

procedure Lone(const a: array of LongInt);
begin
  seenLen := Length(a);
  seenLow := Low(a);
  seenHigh := High(a);
end;

begin
  fails := 0;
  seenLen := -99; seenLow := -99; seenHigh := -99;

  Lone(nil);
  Check('Length of a nil open array', seenLen, 0);
  Check('Low of a nil open array', seenLow, 0);
  Check('High of a nil open array', seenHigh, -1);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('NILOPENLAX OK');
end.
