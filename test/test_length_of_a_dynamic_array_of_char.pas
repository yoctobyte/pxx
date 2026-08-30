{ Length of a DYNAMIC `array of Char` is the element count, not 1.

  The compile-time Char fold in ParseFactorCore excluded a STATIC array of Char
  by its capacity (ASTCharArrayCap), which is < 0 for a dynamic array exactly as
  it is for a bare Char — so `Length(w)` on `w: array of Char` folded to the
  constant 1 while High(w) answered 5 and the elements read back correctly. The
  fold replaced the call outright, so no backend ever saw it.

  Every row here is an FPC 3.2.2 answer. The non-dyn rows are the point of the
  test as much as the dyn one: the fix widens a guard, and a guard that is
  widened too far breaks `Length(c)` on a bare Char, which is what the arm is
  legitimately for. bug-p-length-of-a-dynamic-array-of-char-returns-1 }
{$mode objfpc}{$H+}
procedure TakesOpen(const a: array of Char);
begin WriteLn('openparam=', Length(a)); end;
var w: array of Char; s: array[0..7] of Char; c: Char;
    d: array of WideChar; b: array of Byte; i: Integer;
begin
  SetLength(w, 6); SetLength(d, 3); SetLength(b, 6);
  for i := 0 to 5 do w[i] := Chr(65 + i);
  c := 'x';
  WriteLn('dyn char  =', Length(w));
  WriteLn('static char=', Length(s));
  WriteLn('bare char =', Length(c));
  WriteLn('lit       =', Length('hello'));
  WriteLn('widechar  =', Length(d));
  WriteLn('byte      =', Length(b));
  WriteLn('high dyn  =', High(w));
  WriteLn('elems     =', w[0], w[5]);
  TakesOpen(w);
end.
