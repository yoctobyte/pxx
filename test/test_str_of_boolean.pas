program test_str_of_boolean;
{ `Str(b, s)` must render a Boolean the way everything else in this compiler
  already does -- TRUE/FALSE, which is also what FPC gives.

  WHY THE EXPECTED VALUES DISCRIMINATE. The failure this pins is not a crash
  and not a refusal: before the fix, Str's dispatch had no Boolean arm, so a
  Boolean fell through to StrInt and printed `1`. A row expecting `1` would
  have passed against the bug AND against a correct compiler that happened to
  print the ordinal, so the expected value here (TRUE) is one the broken path
  cannot produce. `writeln(b)` two columns over already printed TRUE, which is
  what made this one compiler rendering one value two ways.

  The QWord and Integer rows are NOT filler. Routing Boolean to StrBool meant
  deleting the `<> tyBoolean` exclusion from the StrQWord arm, which existed
  only to keep an unsigned Boolean off StrQWord. These rows are what says that
  deletion did not move the unsigned or the signed dispatch.
  bug-p-str-of-a-boolean-formats-it-as-a-digit / feature-writeln-as-library }
var
  s: ShortString;
  b: Boolean;
  q: QWord;
  i: Integer;
  n: Integer;
begin
  b := True;  Str(b, s); writeln('t=', s);
  b := False; Str(b, s); writeln('f=', s);

  { the same value through the OTHER renderer -- the pair is the point }
  b := True;  writeln('wt=', b);
  b := False; writeln('wf=', b);

  { width, literal and variable: StrBool right-justifies through StrStrW, and
    a width narrower than the word must not truncate it }
  b := True;  Str(b:8, s); writeln('w8=[', s, ']');
  b := False; Str(b:8, s); writeln('w8f=[', s, ']');
  b := True;  Str(b:2, s); writeln('w2=[', s, ']');
  n := 6; b := True; Str(b:n, s); writeln('wv=[', s, ']');

  { the two dispatch arms either side of the new one }
  q := 18446744073709551615; Str(q, s); writeln('q=', s);
  i := -42; Str(i, s); writeln('i=', s);

  writeln('STR BOOL OK');
end.
