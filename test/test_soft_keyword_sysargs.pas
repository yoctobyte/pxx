program test_soft_keyword_sysargs;
{ The remaining hard-keyword intrinsics became soft keywords: SysOpen, SysRead,
  SysWrite, SysClose, SysFchmod, ArgCount/ParamCount, ArgStr/ParamStr
  (bug-p-nine-intrinsic-spellings-are-hard-keywords-so-they-cannot-be-user-names,
  bug-p-sysopen-intrinsic-shadows-a-user-function-name). Sibling of
  test_soft_keyword_length.pas, same contract: every spelling is declarable as a
  routine / variable / parameter / field / method name, and the intrinsic forms
  are untouched where the name is not shadowed.

  ParamCount is the one soft intrinsic with NO '(' requirement -- FPC code writes
  it bare (`for i := 1 to ParamCount do`) -- so its guard is the shadow test
  alone. Rows 12 and 13 are what hold that: bare-and-unshadowed must still be the
  intrinsic, and a user routine of the name must still win.

  NOT FLAKY UNDER -uPXX_MANAGED_STRING: row 15 (ParamStr(0)[1]) refuses on the
  FROZEN path, and so does it on pin v404, so it is not this test's doing --
  bug-b-copy-cannot-compile-at-all-on-the-frozen-string-path. -u UNdefines;
  PXX_MANAGED_STRING is ON by default, so the suite's default run is the -d
  half and this file is 20/20 there, under -Mobjfpc and -Mdelphi as well. }

var
  okCount: Integer;

procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin writeln('ok ', n); okCount := okCount + 1; end
  else writeln('FAIL ', n);
end;

{ 1-7: every spelling as a ROUTINE name. This is the half that used to fail at
  the DECLARATION with `expected name`, before any call could be reached. }
function SysOpen: Integer;   begin SysOpen := 1; end;
function SysRead: Integer;   begin SysRead := 2; end;
function SysWrite: Integer;  begin SysWrite := 3; end;
function SysClose: Integer;  begin SysClose := 4; end;
function SysFchmod: Integer; begin SysFchmod := 5; end;
function ArgCount: Integer;  begin ArgCount := 6; end;
function ArgStr: Integer;    begin ArgStr := 7; end;

{ as PARAMETER names }
function ParamNames(ParamCount, ParamStr, SysOpen: Integer): Integer;
begin ParamNames := ParamCount + ParamStr + SysOpen; end;

{ as LOCAL variable names — shadowing the intrinsic in this scope only }
function LocalNames: Integer;
var ParamCount, ParamStr, SysRead, SysFchmod: Integer;
begin
  ParamCount := 10; ParamStr := 20; SysRead := 30; SysFchmod := 40;
  LocalNames := ParamCount + ParamStr + SysRead + SysFchmod;
end;

{ as RECORD FIELD and as METHOD names }
type
  TRec = record ParamCount: Integer; SysClose: Integer; end;
  TCls = class
    ParamStr: Integer;
    function SysWrite(x: Integer): Integer;
  end;

function TCls.SysWrite(x: Integer): Integer;
begin Result := x * 3; end;

var
  r: TRec;
  c: TCls;
  path: string[255];
  fd, n, i, total: Integer;
  buf: array[0..15] of Byte;
  s: string[255];

begin
  okCount := 0;

  { the seven spellings as routine names, called by name }
  Chk(1, SysOpen = 1);
  Chk(2, SysRead = 2);
  Chk(3, SysWrite = 3);
  Chk(4, SysClose = 4);
  Chk(5, SysFchmod = 5);
  Chk(6, ArgCount = 6);
  Chk(7, ArgStr = 7);

  Chk(8, ParamNames(1, 2, 4) = 7);
  Chk(9, LocalNames = 100);

  r.ParamCount := 11; r.SysClose := 22;
  Chk(10, (r.ParamCount = 11) and (r.SysClose = 22));

  c := TCls.Create;
  c.ParamStr := 33;
  Chk(11, (c.ParamStr = 33) and (c.SysWrite(4) = 12));

  { the INTRINSICS, unshadowed, in a scope where no user name is in play.
    ParamCount is written BARE here on purpose -- the no-paren form is the one
    the guard cannot check a lookahead for. }
  Chk(12, System.ParamCount >= 0);
  total := 0;
  for i := 0 to System.ParamCount do total := total + 1;
  Chk(13, total = System.ParamCount + 1);

  { ParamStr through the expression path, the [i] postfix, and the two-argument
    statement form, all against argv[0], which always exists. }
  s := System.ParamStr(0);
  Chk(14, Length(s) > 0);
  Chk(15, System.ParamStr(0)[1] = s[1]);
  System.ArgStr(0, path);
  Chk(16, path = s);

  { the sys* file intrinsics: open argv[0] read-only, read from it, close it.
    SysOpen wants a string VARIABLE, not an expression -- that is its own rule
    and predates the soft-keyword change. }
  fd := System.SysOpen(path, 0);
  Chk(17, fd >= 0);
  n := System.SysRead(fd, buf, 4);
  Chk(18, n = 4);
  Chk(19, buf[0] = 127);                  { ELF magic byte 0 }
  System.SysClose(fd);

  { SysWrite's STATEMENT form, to stdout, and SysFchmod's on a closed fd, which
    fails harmlessly -- both are here to prove the statement dispatch is wired,
    not to test the syscalls. }
  buf[0] := Ord('!'); buf[1] := 10;
  System.SysWrite(1, buf, 2);
  System.SysFchmod(-1, 384);
  Chk(20, True);

  writeln('total ok ', okCount, ' / 20');
end.
