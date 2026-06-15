program test_varrec_alloc_after;

{ Regression: an `array of const` lowers to a dyn-array of TVarRec (an UNMANAGED
  record). GetOrAllocSymRTTI used to record the element size as TypeSize(tyRecord)
  = 8 (a pointer-width placeholder) instead of RecSize(TVarRec) = 16, so
  SetLength under-allocated: a 2-element array got 16 bytes and element 1 (offset
  16) overran into adjacent free heap. It survived only if read immediately; any
  allocation between construction and the read clobbered it.

  Here the consumer performs heap allocations (string building) BEFORE reading
  the later elements, so an under-allocated element 1+ would be corrupted. This
  surfaced compiling the AArch64 self-host (EmitAsmA64 builds `['b %', offset]`
  then does string work before reading the integer hole). }

procedure check(const items: array of const);
var i, n: Integer; s: AnsiString;
begin
  n := Length(items);
  s := '';
  for i := 0 to 200 do
    s := s + 'x';                 { force allocations after construction }
  write('n=', n, ':');
  for i := 0 to n - 1 do
    if items[i].VType = vtAnsiString then
      write(' S')
    else
      write(' ', items[i].VInteger);
  writeln;
end;

begin
  check(['hi', 42]);
  check([10, 20, 30, 40]);
  check(['s', 11, 22]);
end.
