unit prepasserr_mid;
{ FPC's ncon.pas:968 and symsym.pas:2800 in miniature: a WIDTH LADDER whose
  final `{$else}` is a `{$error}`. That is the idiom a compiler's own source
  uses to refuse an unsupported configuration, and it is why this failure is
  expensive -- the message reads like a true statement about the program.

  The pre-pass cannot resolve `sizeof(tprepasswidechar)` from here (the type is
  one unit further and probes do not nest), an unresolvable `{$if}` answers
  False, so every arm tests false and control reaches the `{$else}`. Before the
  fix the PRE-PASS raised that `{$error}` and halted the compile; fpc 3.2.2
  compiles this and Which answers 2. }
interface
uses prepasserr_base;
function Which: Integer;
implementation
function Which: Integer;
begin
{$if sizeof(tprepasswidechar) = 2}
  Which := 2;
{$elseif sizeof(tprepasswidechar) = 4}
  Which := 4;
{$else}
  {$error Unsupported tprepasswidechar size}
{$endif}
end;
end.
