unit menu;
{ A vertical selection list for the TUI library — the pure navigation logic
  (which item is selected after a key). Rendering is the caller's job (loop the
  items, draw each with ScreenWrite, give the selected row ATTR_REVERSE), the
  same "you render it" split as lineedit.

  NOTE: a `MenuDraw(... const items: array of AnsiString ...)` helper was removed
  because a const open-array of a managed element loses its length and crashes —
  see bug-const-open-array-managed-elem-length. Re-add it once that is fixed. }

interface

uses screen;   { KEY_* constants }

{ Return the new selected index after applying `key` to a `count`-item list.
  Up/Down move (wrapping when `wrap`), Home/End jump to the ends, anything else
  leaves it unchanged. The index is always clamped to 0..count-1. }
function MenuNavigate(count, selected, key: Integer; wrap: Boolean): Integer;

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

end.
