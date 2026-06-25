{ Include with a JEDI-style guard whose body contains a COMMENT quoting
  conditional directives. On a 2nd include the guard is inactive, so the body
  (and this comment) is skipped — the skip must NOT treat the quoted ifdef/endif
  as real directives (bug-conditional-directive-miscount-synautil). }
{$IFNDEF COND_COMMENT_GUARD_INC}
{$DEFINE COND_COMMENT_GUARD_INC}
{ docs: written as "{$IFNDEF CLR} {$IFDEF MSWINDOWS}" in real headers }
const GuardVal = 42;
{$ENDIF COND_COMMENT_GUARD_INC}
