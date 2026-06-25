program test_cond_comment_skip;
{ The include is pulled twice; the 2nd time the guard is inactive and its body
  — including a comment that quotes conditional directives — must be skipped
  without corrupting the conditional-nesting stack. }
{$I cond_comment_guard.inc}
{$I cond_comment_guard.inc}
begin
  writeln(GuardVal);
end.
