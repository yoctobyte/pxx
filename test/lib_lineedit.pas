program lib_lineedit;
{ Unit test for the line-edit widget: drive it with key events and assert the
  exact buffer + cursor after each, including insert/backspace/delete and the
  navigation keys, plus that it reports non-edit keys (Enter) as not consumed. }

uses screen, lineedit;

var
  e: TLineEdit;
  fails, b: Integer;

procedure Expect(const tag: string; const wantText: AnsiString; wantCur: Integer);
begin
  if (e.Text = wantText) and (e.Cursor = wantCur) then
    writeln(tag, '=ok')
  else
  begin
    writeln(tag, '=bad [', e.Text, '] cur=', e.Cursor);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  LineEditInit(e);

  b := Ord(LineEditKey(e, Ord('h')));
  b := Ord(LineEditKey(e, Ord('i')));
  Expect('type', 'hi', 2);

  LineEditKey(e, KEY_LEFT);
  Expect('left', 'hi', 1);

  LineEditKey(e, Ord('X'));         { insert mid-string }
  Expect('insert-mid', 'hXi', 2);

  LineEditKey(e, 127);              { backspace removes 'X' }
  Expect('backspace', 'hi', 1);

  LineEditKey(e, KEY_HOME);
  Expect('home', 'hi', 0);

  LineEditKey(e, KEY_DEL);          { delete char at cursor ('h') }
  Expect('delete', 'i', 0);

  LineEditKey(e, KEY_END);
  Expect('end', 'i', 1);

  LineEditKey(e, 127);              { backspace at end -> empty }
  Expect('bs-empty', '', 0);

  LineEditKey(e, KEY_LEFT);         { left at 0 -> no-op }
  Expect('left-edge', '', 0);

  LineEditKey(e, 127);              { backspace at 0 -> no-op }
  Expect('bs-edge', '', 0);

  { Enter is not an edit key -> not consumed. }
  if LineEditKey(e, 13) then
  begin
    writeln('enter=bad'); fails := fails + 1;
  end
  else
    writeln('enter=ok');

  LineEditSet(e, 'abc');
  Expect('set', 'abc', 3);

  if fails = 0 then writeln('ALL OK') else writeln('FAILS=', fails);
end.
