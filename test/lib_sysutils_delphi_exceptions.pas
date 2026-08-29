{ The three SysUtils gaps a vendored rtl-generics hits
  (feature-sysutils-delphi-exception-api-gaps-found-by-rtl-generics):
  EArgumentOutOfRangeException, Exception.CreateRes/CreateResFmt, and
  System.Error over TRuntimeError.

  Compiles and runs under FPC 3.2.2 unmodified, and every expectation below was
  produced BY it -- including the two nobody would guess:

    * TRuntimeError's tail is not Delphi's. FPC 3.2.2 ends the enumeration
      reQuit / reCodesetConversion / reNoDynLibsSupport / reThreadError where
      Delphi has the monitor errors, so it has 29 members and reRangeError is 4.
      Recalling that list gets it wrong; this file asserts the ordinal a
      vendored `case` would compare against.
    * EArgumentOutOfRangeException is a DESCENDANT of EArgumentException, not a
      sibling, so `on E: EArgumentException` catches it. Asserted rather than
      assumed, because getting it wrong makes a handler silently not fire.

  WHERE IT STOPS BEING A DIFFERENTIAL, EXACTLY. The first 18 rows were run under
  FPC 3.2.2 and are byte-identical to it. The three `error_*` rows are NOT: under
  FPC, `Error(reRangeError)` HALTS with an uncatchable runtime error 201, and the
  FPC run dies there rather than printing them. Ours raises a catchable
  exception, and that is a deliberate divergence, not a shortfall:

    * It is our domain. CLAUDE.md -- a strict flag governs how source is
      COMPILED, not how a program DIES; "we seek LANGUAGE compliance, not
      error-handling compliance".
    * It matches OUR runtime, which is the consistency that actually matters
      here: pxx already surfaces division by zero as a catchable EDivByZero and
      a bad StrToInt as EConvertError (measured). An Error() that halted would
      be the odd one out in its own RTL.

  The cost is real and is stated rather than hidden: a catchable Error can be
  swallowed by a surrounding `try..except`, so a "this cannot happen" arm that
  DOES happen becomes a handled path instead of a stop. Every one of the 7 sites
  in generics.defaults.pas is such an arm. If that ever bites, the fix is to
  halt, and this paragraph is the record of the choice.

  So: which class Error raises, and any error number, is NOT asserted -- only
  that it raises, and that reNone does not. Chasing FPC's numbers is explicitly
  low-prio by the owner's ruling.

  Nor does it spell CreateRes's argument the way real code does. FPC writes
  `CreateRes(@SSomeResourceString)`; here the source is a typed const, because
  `@` of a resourcestring is a compile error in pxx
  ([[bug-p-a-resourcestring-is-not-addressable]], filed). The constructor takes
  any ^string and is unaffected -- it is the call-site spelling that waits. }
program lib_sysutils_delphi_exceptions;

{$MODE OBJFPC}{$H+}

uses sysutils;

const
  SArgOOR: string = 'Argument out of range';
  SFmtOne: string = 'value %d is out of range';

var
  fails: Integer;

procedure Chk(const name, got, want: string);
begin
  if got = want then
    WriteLn(name, '=ok')
  else
  begin
    WriteLn(name, '=FAIL got<', got, '> want<', want, '>');
    Inc(fails);
  end;
end;

procedure ChkB(const name: string; got, want: Boolean);
begin
  if got = want then WriteLn(name, '=ok')
  else begin WriteLn(name, '=FAIL'); Inc(fails); end;
end;

var
  raised: Boolean;
  cls, msg: string;

begin
  fails := 0;

  { ---- 1. EArgumentOutOfRangeException, and its ANCESTRY ---- }
  raised := False; cls := ''; msg := '';
  try
    raise EArgumentOutOfRangeException.Create('plain');
  except
    on E: EArgumentException do
    begin
      raised := True; cls := E.ClassName; msg := E.Message;
    end;
  end;
  ChkB('oor_caught_as_argument_exception', raised, True);
  Chk('oor_classname', cls, 'EArgumentOutOfRangeException');
  Chk('oor_message', msg, 'plain');

  { it is still an Exception, and `is` distinguishes it from its parent }
  ChkB('oor_is_exception', EArgumentOutOfRangeException.Create('x') is Exception, True);
  ChkB('argexc_is_not_oor',
       EArgumentException.Create('x') is EArgumentOutOfRangeException, False);

  { ---- 2. CreateRes / CreateResFmt: dereference and construct ---- }
  msg := '';
  try
    raise EArgumentOutOfRangeException.CreateRes(@SArgOOR);
  except
    on E: Exception do msg := E.Message;
  end;
  Chk('createres_message', msg, 'Argument out of range');

  msg := ''; cls := '';
  try
    raise EArgumentOutOfRangeException.CreateResFmt(@SFmtOne, [42]);
  except
    on E: Exception do begin msg := E.Message; cls := E.ClassName; end;
  end;
  Chk('createresfmt_message', msg, 'value 42 is out of range');
  Chk('createresfmt_keeps_class', cls, 'EArgumentOutOfRangeException');

  { ---- 3. TRuntimeError ordinals, and that Error() raises ---- }
  Chk('re_none',        IntToStr(Ord(reNone)),        '0');
  Chk('re_outofmemory', IntToStr(Ord(reOutOfMemory)), '1');
  Chk('re_invalidptr',  IntToStr(Ord(reInvalidPtr)),  '2');
  Chk('re_divbyzero',   IntToStr(Ord(reDivByZero)),   '3');
  Chk('re_rangeerror',  IntToStr(Ord(reRangeError)),  '4');
  Chk('re_intoverflow', IntToStr(Ord(reIntOverflow)), '5');
  Chk('re_invalidcast', IntToStr(Ord(reInvalidCast)), '10');
  Chk('re_assertfail',  IntToStr(Ord(reAssertionFailed)), '21');
  { the tail that is FPC's and not Delphi's -- the reason this block exists }
  Chk('re_quit',        IntToStr(Ord(reQuit)),        '25');
  Chk('re_threaderror', IntToStr(Ord(reThreadError)), '28');

  { Error RAISES rather than returning. Which class, and any error number, is
    ours by the error-handling ruling and is NOT asserted. }
  raised := False;
  try
    Error(reRangeError);
  except
    on E: Exception do raised := True;
  end;
  ChkB('error_raises', raised, True);

  raised := False;
  try
    Error(reInvalidCast);
  except
    on E: Exception do raised := True;
  end;
  ChkB('error_raises_invalidcast', raised, True);

  { reNone is the one member that must NOT raise -- it is the "no error" value,
    and an Error(reNone) that threw would turn a success path into a failure }
  raised := False;
  try
    Error(reNone);
  except
    on E: Exception do raised := True;
  end;
  ChkB('error_none_does_not_raise', raised, False);

  if fails = 0 then WriteLn('SYSUTILS-DELPHI-EXC OK')
  else WriteLn('SYSUTILS-DELPHI-EXC ', fails, ' FAILED');
end.
