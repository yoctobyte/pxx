{ Missing FPC surface found by the differential probe: Eoln, the legacy
  TSeekOrigin names, and IncMonth.

  Every expectation is FPC's own output for the same program, measured — not
  read off documentation, which is the method note the ticket
  (feature-b-rtl-missing-fpc-surface-2026-08) insists on for exactly these two:
  IncMonth's clamp and Eoln's treatment of CR are both easy to state slightly
  wrong.

  Two of the ticket's four items turned out to be already implemented when
  measured — TStringList.Sorted/Duplicates in full, and the MODERN TSeekOrigin
  names — so what is asserted here is the remainder plus a regression guard on
  the Sorted behaviour that was found working.

  The IncMonth line that catches a wrong implementation is +2 from the 31st:
  the clamp applies to the ORIGINAL day against the FINAL month, so Jan 31 + 2
  is Mar 31, not the Feb 28 that clamping month-by-month would give. }
program lib_fpc_surface_2026_08;

uses sysutils, classes, textfile;

var
  failures: Integer;

procedure CheckStr(const got, want, what: string);
begin
  if got <> want then
  begin
    writeln('FAIL: ', what, ' got <', got, '> want <', want, '>');
    failures := failures + 1;
  end;
end;

procedure CheckInt(got, want: Integer; const what: string);
begin
  if got <> want then
  begin
    writeln('FAIL: ', what, ' got ', got, ' want ', want);
    failures := failures + 1;
  end;
end;

procedure WriteRaw(const path, content: AnsiString);
var f: Text;
begin
  Assign(f, path);
  Rewrite(f);
  TextWrite(f, content);
  Close(f);
end;

{ Walk the file the way character-at-a-time code does: at Eoln consume the line
  break, otherwise take the character. Mirrors the FPC probe exactly. }
function Walk(const path: AnsiString): AnsiString;
var f: Text; c: Char; s, junk: AnsiString; n: Integer;
begin
  Assign(f, path);
  Reset(f);
  s := '';
  n := 0;
  while (not Eof(f)) and (n < 20) do
  begin
    if Eoln(f) then
    begin
      s := s + '[1R]';
      TextReadLn(f, junk);
    end
    else
    begin
      TextReadChar(f, c);
      s := s + '[0:' + IntToStr(Ord(c)) + ']';
    end;
    n := n + 1;
  end;
  if Eoln(f) then s := s + ' eofEoln=TRUE' else s := s + ' eofEoln=FALSE';
  Close(f);
  Result := s;
end;

var
  pa, pb, pc, pd: AnsiString;
  d: TDateTime;
  sl: TStringList;
  i: Integer;
  acc: AnsiString;
  f: Text;
begin
  failures := 0;
  pa := '/tmp/lib_fpcsurf_a.txt';
  pb := '/tmp/lib_fpcsurf_b.txt';
  pc := '/tmp/lib_fpcsurf_c.txt';
  pd := '/tmp/lib_fpcsurf_d.txt';
  WriteRaw(pa, 'ab' + Chr(10) + 'c' + Chr(10));
  WriteRaw(pb, 'a' + Chr(13) + Chr(10) + 'b' + Chr(10));
  WriteRaw(pc, 'xy');
  WriteRaw(pd, Chr(10));

  { --- 1. Eoln --- }
  CheckStr(Walk(pa), '[0:97][0:98][1R][0:99][1R] eofEoln=TRUE', 'Eoln over "ab\ncd\n"');
  CheckStr(Walk(pb), '[0:97][1R][0:98][1R] eofEoln=TRUE', 'Eoln treats CR as a line end');
  CheckStr(Walk(pc), '[0:120][0:121] eofEoln=TRUE', 'Eoln true at EOF with no trailing newline');
  CheckStr(Walk(pd), '[1R] eofEoln=TRUE', 'Eoln on a file that is just a newline');

  { --- 2. TSeekOrigin, both spellings, same values --- }
  CheckInt(Ord(soFromBeginning), 0, 'Ord(soFromBeginning)');
  CheckInt(Ord(soFromCurrent), 1, 'Ord(soFromCurrent)');
  CheckInt(Ord(soFromEnd), 2, 'Ord(soFromEnd)');
  CheckInt(Ord(soBeginning), 0, 'Ord(soBeginning)');
  CheckInt(Ord(soCurrent), 1, 'Ord(soCurrent)');
  CheckInt(Ord(soEnd), 2, 'Ord(soEnd)');

  { --- 3. TStringList.Sorted / Duplicates (found already working; guarded) --- }
  sl := TStringList.Create;
  sl.Add('pear'); sl.Add('apple'); sl.Add('fig');
  sl.Sorted := True;
  acc := '';
  for i := 0 to sl.Count - 1 do acc := acc + ' ' + sl[i];
  CheckStr(acc, ' apple fig pear', 'Sorted := True orders the list');
  sl.Add('banana');
  acc := '';
  for i := 0 to sl.Count - 1 do acc := acc + ' ' + sl[i];
  CheckStr(acc, ' apple banana fig pear', 'Add into a sorted list lands in order');
  CheckInt(sl.IndexOf('fig'), 2, 'IndexOf in a sorted list');
  CheckInt(sl.IndexOf('zzz'), -1, 'IndexOf of a missing string');
  sl.Duplicates := dupIgnore;
  sl.Add('fig');
  CheckInt(sl.Count, 4, 'dupIgnore drops the duplicate');
  sl.Duplicates := dupAccept;
  sl.Add('fig');
  CheckInt(sl.Count, 5, 'dupAccept keeps it');
  sl.Sorted := False;
  sl.Add('aaa');
  CheckStr(sl[sl.Count - 1], 'aaa', 'Add appends once Sorted is off');
  CheckInt(Ord(dupIgnore), 0, 'Ord(dupIgnore)');
  CheckInt(Ord(dupAccept), 1, 'Ord(dupAccept)');
  CheckInt(Ord(dupError), 2, 'Ord(dupError)');
  sl.Free;

  { --- 4. IncMonth, clamp and all --- }
  d := EncodeDate(2026, 1, 31);
  CheckStr(FormatDateTime('yyyy-mm-dd', IncMonth(d, 1)), '2026-02-28', 'IncMonth clamps Jan 31 to Feb 28');
  CheckStr(FormatDateTime('yyyy-mm-dd', IncMonth(d, 2)), '2026-03-31', 'IncMonth does not compound the clamp');
  CheckStr(FormatDateTime('yyyy-mm-dd', IncMonth(d, 12)), '2027-01-31', 'IncMonth rolls the year');
  CheckStr(FormatDateTime('yyyy-mm-dd', IncMonth(d, -1)), '2025-12-31', 'IncMonth backwards across a year');
  CheckStr(FormatDateTime('yyyy-mm-dd', IncMonth(d, 0)), '2026-01-31', 'IncMonth by 0');
  CheckStr(FormatDateTime('yyyy-mm-dd', IncMonth(EncodeDate(2024, 1, 31), 1)), '2024-02-29', 'IncMonth clamps to a LEAP February');
  CheckStr(FormatDateTime('yyyy-mm-dd', IncMonth(EncodeDate(2026, 3, 31), -1)), '2026-02-28', 'IncMonth clamps going backwards');
  CheckStr(FormatDateTime('yyyy-mm-dd', IncMonth(EncodeDate(2026, 12, 31), 1)), '2027-01-31', 'IncMonth over the year boundary');
  { the time of day survives — FPC keeps it, and a re-encode would round it }
  d := EncodeDate(2026, 1, 15) + EncodeTime(13, 45, 30, 0);
  CheckStr(FormatDateTime('yyyy-mm-dd hh:nn:ss', IncMonth(d, 1)), '2026-02-15 13:45:30', 'IncMonth preserves the time');
  { time survives the CLAMP too — the clamped path rebuilds the date, so this is
    where a re-encode would lose or round it }
  d := EncodeDate(2026, 1, 31) + EncodeTime(23, 59, 59, 0);
  CheckStr(FormatDateTime('yyyy-mm-dd hh:nn:ss', IncMonth(d, 1)), '2026-02-28 23:59:59', 'IncMonth preserves the time across a clamp');

  Assign(f, pa); Erase(f);
  Assign(f, pb); Erase(f);
  Assign(f, pc); Erase(f);
  Assign(f, pd); Erase(f);

  if failures = 0 then writeln('FPCSURFACE OK')
  else writeln('FPCSURFACE ', failures, ' FAILURES');
end.
