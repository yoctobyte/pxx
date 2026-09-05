program test_ifopt_guards_an_include;
{ A dollar-I inside a dollar-IFOPT arm. This is a SECOND path with its own copy
  of the IFOPT decision -- ExpandIncludes in elfwriter.inc, the pre-pass that
  splices includes in before the lexer runs -- and it carried the identical
  hardwired `cond := False` that ParseFactorCore's copy had, left behind when
  that one was fixed. devdocs/dev/normalise-dont-special-case.md, exactly: the
  second path is the one that stays broken.

  IT FAILS WORSE HERE THAN A WRONG ARM DOES. The pre-pass decides whether the
  include is LOADED at all, so the file was dropped from the text, the real
  lexer then took the true arm and found it empty, and NEITHER arm ran. Pin
  v404 prints only 'done' for row 1 below -- no included line, no else line, no
  diagnostic.

  Row 2 is the negative that stops the fix from being "always load": a letter
  whose state really is off must still take the else arm, or a source with two
  arms and one platform's include would start refusing on a missing file.
  Measured: a missing include in a dead branch is fine, in a live one it is a
  hard error, so guessing ON would trade a silent drop for a spurious refusal.

  Both rows agree with fpc 3.2.2 on the same sources. X is used rather than C
  because our C defaults on and fpc's defaults off; X defaults on in both. }

var okCount: Integer;

{ Called ONLY from the include file, so its call count is the measurement:
  the include ran, or it did not. }
procedure IncludeRan;
begin
  WriteLn('the guarded include was loaded');
  okCount := okCount + 1;
end;

procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin WriteLn('ok ', n); okCount := okCount + 1; end
  else WriteLn('FAIL ', n);
end;

var elseTaken1: Boolean;

begin
  okCount := 0;
  elseTaken1 := False;

  { 1. X is on, so the include must be spliced in and RUN. IncludeRan is the
     only thing that increments for this row -- the else arm below deliberately
     does not, so a build that drops the include cannot reach the total.
     Pin v404 takes the else arm here. }
{$IFOPT X+}
  {$I ifoptinc/ifopt_guarded.inc}
{$ELSE}
  elseTaken1 := True;
  WriteLn('FAIL 1: else arm taken with X on, so the include was dropped');
{$ENDIF}

  { 2. R is off by default, so the include must NOT be loaded and the else arm
     must run. If the include were spliced here it would print its own line and
     row 2 would report the wrong count. }
{$IFOPT R+}
  {$I ifoptinc/ifopt_guarded.inc}
  WriteLn('FAIL 2: then arm taken with R off');
{$ELSE}
  Chk(2, not elseTaken1);
{$ENDIF}

  WriteLn('total ok ', okCount, ' / 2');
end.
