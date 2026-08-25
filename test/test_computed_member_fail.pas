{ %FAIL-style negative: `.member` on a memberless COMPUTED VALUE.

  Sibling of test_scalar_member_fail.pas, and the half its refusal did not
  cover. That guard was deliberately narrowed to a declared VARIABLE receiver
  (a `tk`-keyed version refused three working cast-then-deref programs), and
  "not a name" was then read as "leave it alone" — so a CALL RESULT kept the
  silent behaviour the named case had lost: `(F).Twice` on a string-returning F
  printed 113, ord('q'), the receiver's own first byte as an Int32.

  The refusal now lives in RequireRecMember, which every member-dispatch copy
  already calls, so it covers the chained and grouped receivers together rather
  than growing a fifth copy.
  bug-p-a-member-on-a-computed-value-silently-reads-the-values-own-bytes }
program test_computed_member_fail;
function F: string; begin Result := 'q'; end;
begin
  writeln((F).NoSuchMember);
end.
