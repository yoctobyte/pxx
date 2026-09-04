{ {$MESSAGE <severity> text} routes by its first word, and the bare
  {$HINT}/{$NOTE}/{$WARNING} spellings route the same way. A plain
  {$MESSAGE text} keeps its old note-shaped line, so the first word is only a
  severity when it actually is one -- `plain` below is message text.
  bug-p-fatal-directive-is-silently-ignored }
program test_pascal_message_severities;
{$message warning wtext}
{$message hint htext}
{$message plain ptext}
{$hint barehint}
{$note barenote}
{$warning barewarning}
begin
  WriteLn('ok');
end.
