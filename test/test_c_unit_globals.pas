program test_c_unit_globals;
{ See test/c_unit_globals.c — the C-unit path must reserve and initialize
  file-scope globals, resolve a forward-declared static, and find crtl's
  <stdarg.h>. Values are what gcc produces for the same file. }
uses pxxcio, c_unit_globals;
begin
  WriteLn(cu_pick(2));    { bins[2]=4 + base 7 + later(2)=20 -> 31 }
  WriteLn(cu_pick(0));    { 1 + 7 + 0 -> 8 }
end.
