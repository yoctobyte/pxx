program test_nested_include;
{ An include inside an include is ordinary Pascal and FPC expands it. pxx
  expanded only ONE level and left the nested directive in the text, where the
  lexer skipped it as an unknown directive — so the nested file's declarations
  silently vanished and a different program compiled than FPC built from the
  same source (bug-a-a-nested-include-is-silently-dropped).

  Three levels, because a fix that merely adds a second level would pass a
  two-level test. Level 2 lives in a subdirectory and includes level 3 by BARE
  name, so it resolves only if each nesting step searches its OWN file's
  directory. The dead {$ifdef} in level 2 guards the other half: a directive in
  an inactive branch must not be opened at all. }
{$I tinc_nested1.inc}
begin
  writeln(NEST_L1);
  writeln(NEST_L2);
  writeln(NEST_L3);
{$ifdef NEST_L3_SEEN}
  writeln('define-crosses-nesting');
{$else}
  writeln('define-LOST');
{$endif}
end.
