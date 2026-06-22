program lib_cursor;
{ ScreenPlaceCursor writes exactly: move-to-cell (1-based) + show-cursor.
  Captured from stdout so the exact escape bytes are asserted. }
uses screen;
begin
  ScreenInitSize(10, 5);
  ScreenPlaceCursor(3, 2);   { -> ESC[3;4H ESC[?25h }
end.
