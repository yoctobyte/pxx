unit menu;
{ A vertical selection list for the TUI library: the pure navigation logic
  (which item is selected after a key) kept separate from rendering, plus a draw
  helper that highlights the selected row. The caller owns the item list and the
  selected index. }

interface

uses screen;   { KEY_* + draw ops + ATTR_REVERSE }

{ Return the new selected index after applying `key` to a `count`-item list.
  Up/Down move (wrapping when `wrap`), Home/End jump to the ends, anything else
  leaves it unchanged. The index is always clamped to 0..count-1. }
function MenuNavigate(count, selected, key: Integer; wrap: Boolean): Integer;

{ Draw the items down from (x,y), the selected row in reverse video. }
procedure MenuDraw(x, y: Integer; const items: array of AnsiString; selected: Integer);

implementation

function MenuNavigate(count, selected, key: Integer; wrap: Boolean): Integer;
begin
  if count <= 0 then
  begin
    MenuNavigate := 0;
    Exit;
  end;
  if selected < 0 then selected := 0;
  if selected >= count then selected := count - 1;

  if key = KEY_UP then
  begin
    selected := selected - 1;
    if selected < 0 then
    begin
      if wrap then selected := count - 1 else selected := 0;
    end;
  end
  else if key = KEY_DOWN then
  begin
    selected := selected + 1;
    if selected >= count then
    begin
      if wrap then selected := 0 else selected := count - 1;
    end;
  end
  else if key = KEY_HOME then
    selected := 0
  else if key = KEY_END then
    selected := count - 1;

  MenuNavigate := selected;
end;

procedure MenuDraw(x, y: Integer; const items: array of AnsiString; selected: Integer);
var i: Integer;
begin
  for i := 0 to High(items) do
  begin
    if i = selected then
      ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_REVERSE)
    else
      ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_NONE);
    ScreenWrite(x, y + i, items[i]);
  end;
  ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_NONE);
end;

end.
