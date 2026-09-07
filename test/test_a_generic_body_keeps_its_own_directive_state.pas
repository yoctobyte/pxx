program test_a_generic_body_keeps_its_own_directive_state;
{ A DIRECTIVE IS PROCESSED IN THE LEX PASS, so the only record of what was in
  force at a token is a per-token snapshot. A generic template is buffered into
  a pool and spliced back into the token stream AT THE SPECIALIZATION SITE, and
  the splice used to fill those snapshots from the token before it -- i.e. from
  wherever the template happened to be instantiated. So a generic body took its
  {$R}/{$C}/{$H} state from the caller.

  BOTH DIRECTIONS ARE ASSERTED AND THEY FAIL DIFFERENTLY, which is why one is
  not enough:

    * template {$R+} instantiated under {$R-} -- the check is DROPPED and 1234
      silently becomes 210. A wrong value, no diagnostic.
    * template {$R-} instantiated under {$R+} -- a check the template did not
      ask for is INSERTED and the program dies on legal code.

  Three channels rather than one, because the defect is the splice and not the
  switch: {$R} (range checks), {$C} (assertions compiled out) and {$H} (the
  width of a bare `string`). All nine of the token-parallel directive channels
  travel through the same two lines; three independent readouts is what says so.

  THE TWO SPECIALIZATIONS ARE THE POSITIVE CONTROL AND THE TYPE ARGUMENT IS
  IRRELEVANT TO EVERY ANSWER. Site A is compiled {$R-}{$C-}{$H+} and site B
  {$R+}{$C+}{$H-} -- opposite in all three -- and the two blocks below must
  print IDENTICAL rows. If the state came from the site, no arrangement of the
  template could make them agree; if the template's own state travels, nothing
  about the site can make them differ. A single specialization would pass on
  half the bug.

  Oracle: fpc 3.2.2 prints all twelve rows exactly as below.
  bug-p-a-generic-body-takes-its-directive-state-from-the-specialization-site }
{$mode objfpc}{$H+}
uses sysutils;

{$R-}{$C-}{$H+}
type
  generic TG<T> = class
    function RangeOn(l: LongInt): AnsiString;
    function RangeOff(l: LongInt): AnsiString;
    function AssertOn: AnsiString;
    function AssertOff: AnsiString;
    function StrWidthNarrow: LongInt;
    function StrWidthWide: LongInt;
  end;

function TG.RangeOn(l: LongInt): AnsiString;
var b: Byte;
begin
  Result := '';
  try
{$R+}
    b := l;                       { the template asks for the check }
{$R-}
    Result := 'no raise ' + IntToStr(b);
  except
    on E: ERangeError do Result := 'range caught';
  end;
end;

function TG.RangeOff(l: LongInt): AnsiString;
var b: Byte;
begin
  Result := '';
  try
{$R-}
    b := l;                       { ...and here it asks for no check }
    Result := 'no raise ' + IntToStr(b);
  except
    on E: ERangeError do Result := 'range caught';
  end;
end;

function TG.AssertOn: AnsiString;
begin
  try
{$C+}
    Assert(False, 'template says on');
{$C-}
    Result := 'not fired';
  except
    on E: Exception do Result := 'fired ' + E.ClassName;
  end;
end;

function TG.AssertOff: AnsiString;
begin
  try
{$C-}
    Assert(False, 'template says off');
    Result := 'not fired';
  except
    on E: Exception do Result := 'fired ' + E.ClassName;
  end;
end;

function TG.StrWidthNarrow: LongInt;
{$H-}
var s: string;
{$H+}
begin
  s := '';
  Result := SizeOf(s);
end;

function TG.StrWidthWide: LongInt;
{$H+}
var s: string;
begin
  s := '';
  Result := SizeOf(s);
end;

{ ---- site A: every switch OFF ---------------------------------------- }
{$R-}{$C-}{$H+}
type TA = specialize TG<LongInt>;

{ ---- site B: every switch ON, i.e. opposite to A in all three -------- }
{$R+}{$C+}{$H-}
type TB = specialize TG<Int64>;

{$R-}{$C-}{$H+}
procedure Report(const tag: AnsiString; ron, roff, aon, aoff: AnsiString;
                 wn, ww: LongInt);
begin
  WriteLn(tag, ' R+ : ', ron);
  WriteLn(tag, ' R- : ', roff);
  WriteLn(tag, ' C+ : ', aon);
  WriteLn(tag, ' C- : ', aoff);
  WriteLn(tag, ' H- : ', wn);
  WriteLn(tag, ' H+ : ', ww);
end;

var a: TA; b: TB;
begin
  a := TA.Create;
  Report('A', a.RangeOn(1234), a.RangeOff(1234), a.AssertOn, a.AssertOff,
         a.StrWidthNarrow, a.StrWidthWide);
  b := TB.Create;
  Report('B', b.RangeOn(1234), b.RangeOff(1234), b.AssertOn, b.AssertOff,
         b.StrWidthNarrow, b.StrWidthWide);
end.
