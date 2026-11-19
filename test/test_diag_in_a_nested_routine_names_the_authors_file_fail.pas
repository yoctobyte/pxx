program test_diag_in_a_nested_routine_names_the_authors_file_fail;
{ A nested routine's body is lifted and re-parsed after every builtin unit has
  been lexed. An error in it said `in: compiler/builtin/builtinheap.pas` for the
  author's own line 9, whenever the bad name existed somewhere in the RTL
  (UpperCase, IntToStr). It must name no other file: this one is the main file.
  bug-p-a-bodiless-procedure-declaration-is-accepted-and-swallows-the-next-routine }
procedure A;
  procedure B;
  begin WriteLn(UpperCase('x'));
  end;
begin
  B;
end;
begin
  A;
end.
