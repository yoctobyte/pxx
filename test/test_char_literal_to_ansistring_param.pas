program test_char_literal_to_ansistring_param;
{ A Char LITERAL passed to an AnsiString value parameter is a static string
  literal, not a heap block built per call. The value was always right; the
  cost was not -- each call stored the ordinal into a ShortString temp and
  converted it with PXXStrFromLit, one PXXAlloc + copy + free per call. NilPy
  pays it on every variant `<`/`>` (pylib's `PyOrdCheck(a, b, '>')`), which
  was one allocation per compare in lekkerzeilen's chart loop.

  The Makefile row asserts the IR SHAPE of Hot (the literal reaches the call
  as const_str, and no PXXStrFromLit is called) and this program's OUTPUT,
  which guards the risks the retag brings with it: overload resolution must
  still pick the Char overload for a Char literal, and a callee that WRITES
  its copy must not write through into the shared static literal -- the
  second call would then see 'z'. }
{$mode objfpc}{$H+}

procedure Take(const s: AnsiString; var sink: Integer);
begin
  sink := sink + Length(s) + Ord(s[1]);
end;

procedure Hot(var sink: Integer);
begin
  Take('>', sink);
end;

procedure Scribble(s: AnsiString);
begin
  s[1] := 'z';
  write(s, ' ');
end;

procedure Over(c: Char); overload;
begin
  write('char:', c, ' ');
end;

procedure Over(const s: AnsiString); overload;
begin
  write('str:', s, ' ');
end;

var sink, i: Integer;
begin
  sink := 0;
  for i := 1 to 1000 do Hot(sink);
  writeln(sink);
  Scribble('a');
  Scribble('a');
  writeln;
  Over('q');
  Over('qq');
  writeln;
end.
