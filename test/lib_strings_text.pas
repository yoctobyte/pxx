{ TStrings.Text and its byte-level line terminator
  (bug-b-stringlist-text-hardcoded-crlf).

  This file compiles under BOTH pxx and FPC, and every expectation below was
  read off an FPC build of it on this Linux host rather than reasoned about --
  the whole bug was a plausible-looking constant nobody diffed.

  WHY IT NEEDS BYTE ASSERTIONS. `Text` returning CRLF and `Text` returning LF
  print identically to a terminal, and SetText accepts either form, so the
  round-trip Text -> SetText -> Text passes under both. The defect is only
  visible in the LENGTH and in the individual character codes, which is why the
  round-trip test that already existed never caught it -- and why SaveToFile
  silently wrote DOS line endings into files on a Unix host. }
program lib_strings_text;
uses classes, sysutils;

var fails: Integer;

procedure Chk(const what, got, want: string);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=[', got, '] want=[', want, ']'); fails := fails + 1; end;
end;

{ line endings rendered visible, since the difference is invisible otherwise }
function Vis(const s: string): string;
var i: Integer; r: string;
begin
  r := '';
  for i := 1 to Length(s) do
    if s[i] = #13 then r := r + '<CR>'
    else if s[i] = #10 then r := r + '<LF>'
    else r := r + s[i];
  Vis := r;
end;

var
  l: TStringList;
  s: string;
begin
  fails := 0;

  l := TStringList.Create;
  l.Add('p');
  l.Add('q');

  { the platform terminator, one byte on this host -- 'p' LF 'q' LF = 4 }
  Chk('text_len',   IntToStr(Length(l.Text)), '4');
  Chk('text_bytes', Vis(l.Text),              'p<LF>q<LF>');
  Chk('no_cr',      IntToStr(Pos(#13, l.Text)), '0');

  { every line is terminated, including the last -- Text is not a join.
    Through a temporary because `l.Text[i]` -- indexing a getter-backed string
    property -- does not compile yet: bug-p-index-getter-backed-string-property.
    FPC accepts the direct form, so this detour is ours, not the oracle's. }
  s := l.Text;
  Chk('trailing',   IntToStr(Ord(s[Length(s)])), '10');

  { an empty list is an empty string, not a bare terminator }
  l.Clear;
  Chk('empty_len',  IntToStr(Length(l.Text)), '0');

  { one line still gets its terminator }
  l.Add('solo');
  Chk('one_len',    IntToStr(Length(l.Text)), '5');

  { SetText accepts BOTH forms -- that tolerance is what hid the write bug, so
    it is asserted rather than assumed, in both directions }
  l.Text := 'a'#10'b'#10;
  Chk('read_lf',    IntToStr(l.Count) + '|' + l[0] + l[1], '2|ab');
  l.Text := 'a'#13#10'b'#13#10;
  Chk('read_crlf',  IntToStr(l.Count) + '|' + l[0] + l[1], '2|ab');
  { and a CR must not survive INTO the stored line }
  Chk('crlf_strip', IntToStr(Pos(#13, l[0])), '0');

  { a final line with no terminator is still a line }
  l.Text := 'x'#10'y';
  Chk('no_final_nl', IntToStr(l.Count) + '|' + l[1], '2|y');

  { round-trip, which passes under the OLD behaviour too and so proves nothing
    on its own -- kept as the control that says the byte assertions above are
    testing something the round-trip cannot see }
  l.Clear; l.Add('one'); l.Add('two');
  s := l.Text;
  l.Clear; l.Text := s;
  Chk('roundtrip',  IntToStr(l.Count) + '|' + l[0] + '/' + l[1], '2|one/two');

  l.Free;

  if fails = 0 then WriteLn('STRINGSTEXT OK')
  else WriteLn('STRINGSTEXT FAILED ', fails);
end.
