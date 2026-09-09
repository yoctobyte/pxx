{ `$if` CAN READ A CONSTANT AND A TYPE ALIAS THE SOURCE DECLARES.

  Before this change the conditional evaluator knew about DEFINES and about
  `declared()`, and nothing else the source itself says. A name it could not
  resolve fell through to a boolean reading, so

      const ptrbits = 64;   ... a directive testing it ...

  took the ELSE arm silently, and `$if sizeof(TConstPtrUInt) = 8` could not
  be answered at all because `TConstPtrUInt` is an ALIAS and only builtin type
  NAMES had a width. Nineteen of FPC's 207 compiler units stop on this family
  as their first failure (umbrella-pxx-compiles-fpc-itself); the two named
  above are globtype.pas and ncon.pas.

  WHAT EACH HALF OF THIS FILE IS FOR:

  * Every value row is PAIRED with a MIRROR row that must take the other arm
    (`LOCALC = 42` beside `LOCALC = 43`). One row alone cannot fail an
    evaluator that answers True for everything it does not understand, and an
    unresolved expression here answers False, which is the value half of the
    pairs would collide with. Both halves are needed and neither is ballast.
  * The `declared()` and `$ifdef` rows are UNTOUCHED behaviour and are the
    regression control: the probe machinery that answers the new questions is
    the same walk `declared()` already used, and it was made re-entrant for
    this change.
  * `sizeof(LongInt)` is the control for the sizeof arm itself -- a builtin
    type NAME, which never needed an alias hop.

  Every expected value was read off fpc 3.3.1 running this same source, and
  the PINNED compiler refuses the file, so it cannot pass for free.          }
program test_p_a_conditional_directive_can_read_a_source_const;

uses condsrc_unit;

const
  LOCALC   = 42;
  LOCALNEG = -7;
  LOCALHEX = $20;

type
  TLocal1 = cardinal;     { one hop to a builtin }
  TLocal2 = TLocal1;      { two hops }

{$define TESTDEF}

const
  { --- a const the same file declares --- }
{$if LOCALC = 42}      R01 = 'yes'; {$else} R01 = 'no'; {$endif}
{$if LOCALC = 43}      R02 = 'yes'; {$else} R02 = 'no'; {$endif}
{$if LOCALNEG < 0}     R03 = 'yes'; {$else} R03 = 'no'; {$endif}
{$if LOCALNEG > 0}     R04 = 'yes'; {$else} R04 = 'no'; {$endif}
{$if LOCALHEX = 32}    R05 = 'yes'; {$else} R05 = 'no'; {$endif}
{$if LOCALC > UCONST}  R06 = 'yes'; {$else} R06 = 'no'; {$endif}
{$if LOCALC < UCONST}  R07 = 'yes'; {$else} R07 = 'no'; {$endif}

  { --- a const a USED UNIT declares --- }
{$if UCONST = 8}       R08 = 'yes'; {$else} R08 = 'no'; {$endif}
{$if UCONST = 9}       R09 = 'yes'; {$else} R09 = 'no'; {$endif}
{$if UNEG < 0}         R10 = 'yes'; {$else} R10 = 'no'; {$endif}
{$if UHEX = 32}        R11 = 'yes'; {$else} R11 = 'no'; {$endif}

  { --- sizeof through a type ALIAS, same file --- }
{$if sizeof(TLocal1) = 4}  R12 = 'yes'; {$else} R12 = 'no'; {$endif}
{$if sizeof(TLocal2) = 4}  R13 = 'yes'; {$else} R13 = 'no'; {$endif}
{$if sizeof(TLocal2) = 8}  R14 = 'yes'; {$else} R14 = 'no'; {$endif}

  { --- sizeof through a type ALIAS a USED UNIT declares --- }
{$if sizeof(TUAlias1) = 8} R15 = 'yes'; {$else} R15 = 'no'; {$endif}
{$if sizeof(TUAlias2) = 8} R16 = 'yes'; {$else} R16 = 'no'; {$endif}
{$if sizeof(TUAlias2) = 4} R17 = 'yes'; {$else} R17 = 'no'; {$endif}

  { --- untouched behaviour: the controls --- }
{$if sizeof(LongInt) = 4}  R18 = 'yes'; {$else} R18 = 'no'; {$endif}
{$if declared(LOCALC)}     R19 = 'yes'; {$else} R19 = 'no'; {$endif}
{$if declared(NoSuchName)} R20 = 'yes'; {$else} R20 = 'no'; {$endif}
{$if declared(UCONST)}     R21 = 'yes'; {$else} R21 = 'no'; {$endif}
{$ifdef TESTDEF}           R22 = 'yes'; {$else} R22 = 'no'; {$endif}
{$ifdef TESTDEF_NOT}       R23 = 'yes'; {$else} R23 = 'no'; {$endif}

var
  fails: Integer;

procedure Row(const nm, got, want: AnsiString);
begin
  Write(nm, '=', got);
  if got <> want then
  begin
    Write(' WANT ', want);
    fails := fails + 1;
  end;
  WriteLn;
end;

begin
  fails := 0;
  Row('local-const',      R01, 'yes');
  Row('local-const-neg',  R02, 'no');
  Row('local-negative',   R03, 'yes');
  Row('local-negative-n', R04, 'no');
  Row('local-hex',        R05, 'yes');
  Row('two-consts',       R06, 'yes');
  Row('two-consts-neg',   R07, 'no');
  Row('unit-const',       R08, 'yes');
  Row('unit-const-neg',   R09, 'no');
  Row('unit-negative',    R10, 'yes');
  Row('unit-hex',         R11, 'yes');
  Row('local-alias1',     R12, 'yes');
  Row('local-alias2',     R13, 'yes');
  Row('local-alias2-neg', R14, 'no');
  Row('unit-alias1',      R15, 'yes');
  Row('unit-alias2',      R16, 'yes');
  Row('unit-alias2-neg',  R17, 'no');
  Row('builtin-sizeof',   R18, 'yes');
  Row('declared-local',   R19, 'yes');
  Row('declared-absent',  R20, 'no');
  Row('declared-unit',    R21, 'yes');
  Row('ifdef-on',         R22, 'yes');
  Row('ifdef-off',        R23, 'no');
  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CONDSRC OK') else WriteLn('CONDSRC FAILED');
end.
