program test_include_fi_search;
{ {$I} resolves via -Fi include roots after the including file's dir; a miss
  is a hard error (bug-pascal-include-search-silent-miss). }
{$I tinc_fi.cfg}
begin
{$ifdef FROM_FI_DIR}
  writeln('fi-ok');
{$else}
  writeln('fi-FAIL');
{$endif}
end.
