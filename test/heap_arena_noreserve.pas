{ The heap arena is mapped MAP_NORESERVE: the kernel shows that as `nr` in the
  mapping's VmFlags. Without it a 256 MiB reservation is accounted at map time
  and a small guest refuses it.
  bug-a-the-heap-arena-reserves-256-mib-without-map-noreserve-so-a-small-guest-cannot-run-any-allocating-pxx-program }
program heap_arena_noreserve;
var
  f: Text;
  line, s: string;
  inArena, found, nr: Boolean;
begin
  s := 'x';
  s := s + 'y';                       { forces the first heap arena }
  Assign(f, '/proc/self/smaps');
  Reset(f);
  inArena := False; found := False; nr := False;
  while not Eof(f) do
  begin
    ReadLn(f, line);
    if Copy(line, 1, 5) = 'Size:' then
      inArena := Pos(' 262144 kB', line) > 0
    else if inArena and (Copy(line, 1, 8) = 'VmFlags:') then
    begin
      found := True;
      if Pos(' nr', line) > 0 then nr := True;
    end;
  end;
  Close(f);
  WriteLn('arena ', found, ' noreserve ', nr, ' ', s);
end.
