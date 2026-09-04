{ The other spelling of the same stop, which failed for a different reason:
  {$MESSAGE FATAL text} matched the `message` arm, printed `message: FATAL
  text` and carried on. Separate file because the compile aborts.
  bug-p-fatal-directive-is-silently-ignored }
program test_pascal_message_fatal_directive;
{$message fatal 'stop right here'}
begin
  WriteLn('this program must never be built');
end.
