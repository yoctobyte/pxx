program lib_sysutils_executeprocess;
{ sysutils.ExecuteProcess and TExecuteFlags, added for the FPC-compiler-source
  march: cfileutl.pas:136 declares two RequotedExecuteProcess overloads taking
  `Flags: TExecuteFlags = []`, and this unit had neither name.

  EVERY EXPECTED VALUE HERE WAS READ OFF fpc 3.2.2 ON THE SAME SOURCE, not
  predicted from what the implementation ought to do, and every row was then
  checked to answer DIFFERENTLY if the property it names were broken:

  * exit3 answers THREE. A spawn-and-wait that silently failed would answer 0
    or -1, and 0 is what most other rows answer -- so this is the row that
    distinguishes "the child ran" from "the code path returned something".
  * the array form is given a space-bearing POSITIONAL and asserts `$#`. An
    earlier draft passed the space inside the COMMAND STRING and expected 0:
    that row cannot fail, because [sh,-c,'exit $#'] and its re-split
    [sh,-c,exit,$#] both leave $# at 0. With the space in a positional the two
    readings separate -- $0=zero, $1='a b', $2=c gives 2, and a re-split would
    give 3.
  * the string form is whitespace-split and quote-naive, deliberately, because
    fpc's is -- fpc's own cfileutl.pas:142 deprecates it for exactly that. The
    three-word row answers 0 only BECAUSE it split: `sh -c exit 5` runs `exit`
    with $0=5. Unsplit, sh gets one option-string it cannot honour.
  * the one-word row answers 2, which is sh's own refusal of a bare -c. It is
    the only row whose expected value is produced by no default, no failure
    path and no other row.
  * the missing-binary row asserts the EXIT CODE 127 carried on the exception,
    not merely that something was raised. 127 is how a child reports a failed
    exec -- it is already a different process and cannot return a value -- so
    it is the only evidence that the spawn reached exec at all.

  NO ROW USES A `[...]` LITERAL for the array parameter, and that is not style.
  pxx types an array constructor in argument position as a SET, so the
  `array of AnsiString` overload is unreachable for one. Against THESE
  declarations it does not even refuse -- both overloads carry
  `Flags: TExecuteFlags = []`, so a set-shaped candidate is always in scope and
  the wrong overload is selected SILENTLY: `ExecuteProcess('/bin/sh', ['x'])`
  answers 0 here and 2 under fpc. A multi-element literal takes a third door,
  `set item must be one character`. All three measured 2026-09-11 and filed as
  bug-p-an-array-constructor-in-argument-position-is-typed-as-a-set; it does not
  block the corpus, whose call sites pass variables. Using variables here keeps
  this test measuring ExecuteProcess rather than that. }
uses sysutils;

var
  fails: Integer;

procedure Check(const nm: AnsiString; got, want: Integer);
begin
  if got = want then WriteLn(nm, '=yes')
  else begin WriteLn(nm, '=NO got ', got, ' want ', want); Inc(fails); end;
end;

var
  rc: Integer;
  a5: array[0..4] of AnsiString;
  a2: array[0..1] of AnsiString;
  a1: array[0..0] of AnsiString;
  fl: TExecuteFlags;

begin
  fails := 0;

  { A real exit code travels back from the child. }
  a2[0] := '-c'; a2[1] := 'exit 3';
  Check('exit-code-3', ExecuteProcess('/bin/sh', a2), 3);

  a2[1] := 'exit 0';
  Check('exit-code-0', ExecuteProcess('/bin/sh', a2), 0);

  { The array form does not re-split. `a b` must arrive as ONE positional:
    $0=zero, $1=`a b`, $2=c, so $# is 2. Re-split it would be 3. }
  a5[0] := '-c'; a5[1] := 'exit $#';
  a5[2] := 'zero'; a5[3] := 'a b'; a5[4] := 'c';
  Check('array-keeps-a-space', ExecuteProcess('/bin/sh', a5), 2);

  { The string form IS whitespace-split. Three words: sh runs `exit` with
    $0=5, which exits 0. Handed one option-string it could not do that. }
  Check('string-splits-three-words', ExecuteProcess('/bin/sh', '-c exit 5'), 0);

  { One word: sh refuses a bare -c with its own status 2. }
  Check('string-one-word', ExecuteProcess('/bin/sh', '-c'), 2);

  { A missing binary raises EOSError carrying 127. }
  a1[0] := 'x';
  rc := -1;
  try
    rc := ExecuteProcess('/nonexistent/binary/here', a1);
    Inc(fails);
    WriteLn('missing-raises=NO it returned ', rc);
  except
    on E: EOSError do Check('missing-raises-127', E.ErrorCode, 127);
  end;

  { TExecuteFlags exists, is a set, and is accepted. }
  fl := [ExecInheritsHandles];
  a2[0] := '-c'; a2[1] := 'exit 0';
  Check('flags-accepted', ExecuteProcess('/bin/sh', a2, fl), 0);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('EXECPROC OK') else WriteLn('EXECPROC FAIL');
end.
