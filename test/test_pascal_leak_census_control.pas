program test_pascal_leak_census_control;
{ The Pascal leak rows' positive control. Every assert_no_leak row for a
  Pascal program asserts a bound, and a bound only means something if a
  program that DOES leak exceeds it on the same target at the same -O. So this
  builds and drops N managed strings, dynamic arrays and records (live stays
  flat), and with `keep` it hands each one to a reference nothing ever
  releases: one string and one array header per trip leak on purpose, so the
  census must see 2*N more live blocks. Run beside the Pascal rows on every
  target at -O0 and -O2. }
type
  TRec = record
    Name: AnsiString;
    Vals: array of Integer;
  end;
  PRec = ^TRec;

const N = 400;

var i, sink: Integer;
    keep: Boolean;
    s: AnsiString;
    r: TRec;
    p: PRec;

begin
  keep := (ParamCount > 0) and (ParamStr(1) = 'keep');
  sink := 0;
  for i := 1 to N do
  begin
    s := 'item-' + Chr(48 + i mod 10) + Chr(48 + (i div 10) mod 10);
    r.Name := s + '!';
    SetLength(r.Vals, 3 + i mod 5);
    r.Vals[0] := i;
    Inc(sink, Length(r.Name) + Length(r.Vals));
    if keep then
    begin
      { a heap record nobody disposes: its string and its array are
        retained for good -- the deliberate leak }
      New(p);
      p^.Name := r.Name;
      p^.Vals := Copy(r.Vals);
    end;
  end;
  WriteLn('leak-control ', sink);
end.
