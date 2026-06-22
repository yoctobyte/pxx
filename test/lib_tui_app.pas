program lib_tui_app;
{ Integration test: a tiny TUI app wired from screen + menu + lineedit, driven by
  a scripted key sequence (no terminal). It routes navigation keys to the menu
  and the rest to a text field, redraws, and we assert both the resulting state
  and the composed layout — exercising the whole library together. }

uses screen, menu, lineedit;

var
  items: array[0..2] of AnsiString;
  sel, fails: Integer;
  ed: TLineEdit;

procedure HandleKey(k: Integer);
begin
  if (k = KEY_UP) or (k = KEY_DOWN) or (k = KEY_HOME) or (k = KEY_END) then
    sel := MenuNavigate(3, sel, k, True)
  else
    LineEditKey(ed, k);
end;

procedure Redraw;
var i: Integer;
begin
  ScreenClear;
  ScreenWrite(0, 0, 'Menu:');
  for i := 0 to 2 do
  begin
    if i = sel then ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_REVERSE)
    else ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_NONE);
    ScreenWrite(0, 1 + i, items[i]);
  end;
  ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_NONE);
  ScreenWrite(0, 5, 'Name: ' + ed.Text);
end;

procedure CKi(const tag: string; got, want: Integer);
begin
  if got = want then writeln(tag, '=ok')
  else begin writeln(tag, '=bad ', got); fails := fails + 1; end;
end;

procedure CKp(const tag: string; y: Integer; const want: AnsiString);
begin
  if Copy(ScreenDumpRow(y), 1, Length(want)) = want then writeln(tag, '=ok')
  else begin writeln(tag, '=bad [', ScreenDumpRow(y), ']'); fails := fails + 1; end;
end;

begin
  fails := 0;
  items[0] := 'Open'; items[1] := 'Save'; items[2] := 'Quit';
  sel := 0;
  LineEditInit(ed);
  ScreenInitSize(20, 7);

  { script: two downs (Open->Save->Quit), then type "bob" into the field }
  HandleKey(KEY_DOWN);
  HandleKey(KEY_DOWN);
  HandleKey(Ord('b'));
  HandleKey(Ord('o'));
  HandleKey(Ord('b'));
  Redraw;

  CKi('sel',  sel, 2);                 { nav keys routed to the menu }
  CKi('cur',  ed.Cursor, 3);           { char keys routed to the editor }
  CKp('title', 0, 'Menu:');
  CKp('item0', 1, 'Open');
  CKp('item1', 2, 'Save');
  CKp('item2', 3, 'Quit');
  CKp('field', 5, 'Name: bob');

  { now backspace + navigate up: editor and menu independent }
  HandleKey(127);                      { 'bob' -> 'bo' }
  HandleKey(KEY_UP);                   { Quit -> Save }
  Redraw;
  CKi('sel2', sel, 1);
  CKp('field2', 5, 'Name: bo');

  if fails = 0 then writeln('ALL OK') else writeln('FAILS=', fails);
end.
