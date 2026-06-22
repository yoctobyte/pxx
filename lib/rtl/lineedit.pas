unit lineedit;
{ A single-line text input widget for the TUI library — the editable buffer +
  cursor and the keystroke logic, kept separate from any terminal I/O so it is
  fully unit-testable. Feed it the key codes from screen.ScreenReadKey; render it
  yourself (it is just text + a cursor column). }

interface

uses screen;   { KEY_* constants }

type
  TLineEdit = record
    Text: AnsiString;
    Cursor: Integer;     { insertion point, 0 .. Length(Text) }
  end;

procedure LineEditInit(var e: TLineEdit);
procedure LineEditSet(var e: TLineEdit; const s: AnsiString);   { text + cursor at end }

{ Apply one key event (a byte ordinal, or a KEY_* constant). Returns True if the
  editor consumed it (a printable insert or an editing/navigation key), False
  otherwise (e.g. Enter / Esc / unknown) so the caller can act on those. }
function LineEditKey(var e: TLineEdit; key: Integer): Boolean;

implementation

procedure LineEditInit(var e: TLineEdit);
begin
  e.Text := '';
  e.Cursor := 0;
end;

procedure LineEditSet(var e: TLineEdit; const s: AnsiString);
begin
  e.Text := s;
  e.Cursor := Length(s);
end;

function LineEditKey(var e: TLineEdit; key: Integer): Boolean;
var n: Integer;
begin
  n := Length(e.Text);
  if (key >= 32) and (key <= 126) then
  begin
    { insert a printable byte at the cursor }
    e.Text := Copy(e.Text, 1, e.Cursor) + Chr(key) + Copy(e.Text, e.Cursor + 1, n - e.Cursor);
    e.Cursor := e.Cursor + 1;
    LineEditKey := True;
  end
  else if key = 127 then          { Backspace: remove the char before the cursor }
  begin
    if e.Cursor > 0 then
    begin
      e.Text := Copy(e.Text, 1, e.Cursor - 1) + Copy(e.Text, e.Cursor + 1, n - e.Cursor);
      e.Cursor := e.Cursor - 1;
    end;
    LineEditKey := True;
  end
  else if key = KEY_DEL then      { Delete: remove the char at the cursor }
  begin
    if e.Cursor < n then
      e.Text := Copy(e.Text, 1, e.Cursor) + Copy(e.Text, e.Cursor + 2, n - e.Cursor - 1);
    LineEditKey := True;
  end
  else if key = KEY_LEFT then
  begin
    if e.Cursor > 0 then e.Cursor := e.Cursor - 1;
    LineEditKey := True;
  end
  else if key = KEY_RIGHT then
  begin
    if e.Cursor < n then e.Cursor := e.Cursor + 1;
    LineEditKey := True;
  end
  else if key = KEY_HOME then
  begin
    e.Cursor := 0;
    LineEditKey := True;
  end
  else if key = KEY_END then
  begin
    e.Cursor := n;
    LineEditKey := True;
  end
  else
    LineEditKey := False;
end;

end.
