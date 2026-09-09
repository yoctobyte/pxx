program test_a_program_still_needs_a_main_body;
{ NEGATIVE CONTROL for compat-p-a-library-still-requires-a-begin-end-main-body:
  the acceptance is for `library` ONLY. fpc 3.2.2 refuses this exact file, so a
  fix guarded on "no begin follows" instead of on IsLibrary would silently
  accept it and this row is what catches that. }
end.
