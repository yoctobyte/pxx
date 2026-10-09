{ The scheduler's reactor table on ESP. Its four stack columns (saved sp, stack
  base, map length, usable length) are NativeInt, so a 32-bit target keeps one
  word per coroutine per column instead of two. Under --platform=esp there is
  one reactor (MAX_REACTORS = 1) of MAX_CO = 64 rows; with Int64 columns the
  table was 3952 B of .bss, pointer-width it is 2920 B. The Makefile row reads
  the size from PXXDBG=a.datamap; it does not run anything. }
program test_esp_reactor_is_pointer_width;
uses scheduler;

procedure body(arg: Pointer);
begin
end;

begin
  Spawn(@body, nil);
  RunUntilDone;
end.
