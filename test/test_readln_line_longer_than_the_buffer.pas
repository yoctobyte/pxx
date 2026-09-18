program test_readln_line_longer_than_the_buffer;
{ A stdin line longer than the internal line buffer.

  TWO assertions, and the SECOND one is the bug that cost real values: the long
  line must come back WHOLE, and the NEXT readln must get the NEXT line. It
  used to get the TAIL of the previous one — the buffer stopped at its ceiling
  and left the remainder in the fd, so a 5000-byte line silently became two
  lines and every later readln in the program was shifted by one. Nothing about
  the statement that read the long line looked wrong; the wrong value surfaced
  somewhere else entirely.

  It also pinned a divergence between the two spellings of the reader: the
  x86-64 asm stopped one byte earlier than the portable builtin every other
  backend uses, so `len` answered 4095 here and 4096 under --target=riscv32 on
  the same input. Both are now the same demand-allocated growable buffer, so
  neither number can come back.

  No size constant appears here on purpose: the point is that there is no
  ceiling, not that the ceiling moved. FPC 3.2.2 with {$H+} prints the same
  three lines. }
var
  a, b: string;
  i: Integer;
  allA: Boolean;
begin
  readln(a);
  readln(b);
  writeln('len=', Length(a));
  allA := True;
  for i := 1 to Length(a) do
    if a[i] <> 'A' then allA := False;
  writeln('allA=', allA);
  writeln('next=[', b, ']');
end.
