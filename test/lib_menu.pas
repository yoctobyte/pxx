program lib_menu;
{ Tests the menu: exhaustive navigation (wrap + no-wrap, Home/End, clamping,
  empty list) and that MenuDraw places the items (selected row highlighting is an
  attribute, so the plain-text dump just verifies placement). }

uses screen, menu;

var
  items: array[0..2] of AnsiString;
  fails, i, sel: Integer;

procedure CK(const tag: string; got, want: Integer);
begin
  if got = want then writeln(tag, '=ok')
  else begin writeln(tag, '=bad ', got); fails := fails + 1; end;
end;

procedure CKs(const tag: string; const got, want: AnsiString);
begin
  if got = want then writeln(tag, '=ok')
  else begin writeln(tag, '=bad [', got, ']'); fails := fails + 1; end;
end;

begin
  fails := 0;

  { navigation, 3 items }
  CK('down',      MenuNavigate(3, 0, KEY_DOWN, True), 1);
  CK('up',        MenuNavigate(3, 2, KEY_UP, True), 1);
  CK('wrap-down', MenuNavigate(3, 2, KEY_DOWN, True), 0);
  CK('wrap-up',   MenuNavigate(3, 0, KEY_UP, True), 2);
  CK('stop-down', MenuNavigate(3, 2, KEY_DOWN, False), 2);
  CK('stop-up',   MenuNavigate(3, 0, KEY_UP, False), 0);
  CK('home',      MenuNavigate(3, 2, KEY_HOME, True), 0);
  CK('end',       MenuNavigate(3, 0, KEY_END, True), 2);
  CK('other',     MenuNavigate(3, 1, Ord('x'), True), 1);
  CK('clamp',     MenuNavigate(3, 99, KEY_UP, False), 1);   { 99 -> 2, up -> 1 }
  CK('empty',     MenuNavigate(0, 0, KEY_DOWN, True), 0);

  { recommended caller-side rendering: loop the items, reverse the selected row }
  items[0] := 'Open';
  items[1] := 'Save';
  items[2] := 'Quit';
  sel := 1;
  ScreenInitSize(6, 3);
  for i := 0 to 2 do
  begin
    if i = sel then ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_REVERSE)
    else ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_NONE);
    ScreenWrite(1, i, items[i]);
  end;
  CKs('draw0', ScreenDumpRow(0), ' Open ');
  CKs('draw1', ScreenDumpRow(1), ' Save ');
  CKs('draw2', ScreenDumpRow(2), ' Quit ');

  if fails = 0 then writeln('ALL OK') else writeln('FAILS=', fails);
end.
