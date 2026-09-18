{ An ESP-IDF object puts its string literals in .rodata, which the IDF linker
  script places in flash (DROM) -- SRAM given back.
  feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident

  The marker is unique so a linked image can be searched for it: the Makefile
  row links this object and asserts that the literal's bytes sit in a
  non-writable section AND that the .text literal slot holds exactly their
  address. The second half is the one that matters -- a relocation with the
  wrong symbol or addend still links, and only the address comparison sees it.
  --no-ro-data is the control: the same bytes, back in writable .data. }
program esp_obj_rodata;
var
  s: AnsiString;
begin
  s := 'pxx-rodata-marker';
  WriteLn(s);
end.
