{ A `Text` handle reached through a FIELD was not recognised as a file handle at
  all, and the two halves failed in the two worst ways there are.

    WriteLn(F, 'FIELD LINE')   printed `3FIELD LINE` ON THE CONSOLE -- the `3`
                              is the Text record itself, formatted as an
                              ordinary write argument -- and left the file
                              created and EMPTY, exit 0.
    ReadLn(F, s) / EOF(F)     read STDIN, so EOF never came and the program
                              HUNG.

  One missing lookup: `IOHandleSymAt` asks `FindSym` and a field has no Syms[]
  row, so `TextIOFileSym` answered -1 and the CONSOLE path took the call. The
  whole Text lowering was keyed on a symbol index -- `GenMakeIdent(fileSym,
  tyRecord)` at seven sites -- so there was nowhere for a field to go.

  fcl-passrc's `TFileLineReader` (pscanner.pp:433) is exactly this shape: a
  `Text` field with `Assign`/`Reset`/`EOF`/`ReadLn` on it. That is what found
  it, and it is why pscanner.pp compiled and then hung.

  THE GLOBAL-VAR ROWS ARE THE CONTROL AND THEY ARE THE POINT OF THE FILE. The
  bare-symbol fast path is untouched by the fix; these rows say so, and they are
  the rows that would catch a regression in the path every Pascal program uses.

  THE `Emit` METHOD IS THE SECOND CONTROL. Its class declares its own `Write`,
  so `Write(F, ...)` inside it has to choose between the member and the
  intrinsic on a handle the old detector could not see -- the exact silent-empty-
  file shape `IntrinsicNamesSelfMethodHere` already documents for the bare case.
  `Self.Write(...)` reaches the member, and its row proves the member is still
  reachable rather than shadowed away.

  Every row asserts the TEXT READ BACK, not that a call compiled: a write that
  goes to the console instead of the file leaves a file that opens fine and is
  empty, which no compile check and no exit code can see.
  bug-p-a-text-file-reached-through-a-field-is-not-recognised-as-a-file-handle }
{$mode objfpc}
program test_a_text_file_reached_through_a_field;
uses sysutils;
type
  TRec = record F: Text; end;
  TLogger = class
    F: Text;
    Hits: Integer;
    procedure Emit(const path, s: AnsiString);
    procedure Write(const s: AnsiString);          { deliberately shadows }
    function ReadBack(const path: AnsiString): AnsiString;
    function ReadBackSelf(const path: AnsiString): AnsiString;
  end;

procedure TLogger.Write(const s: AnsiString);
begin
  Hits := Hits + Length(s);
end;

procedure TLogger.Emit(const path, s: AnsiString);
begin
  System.Assign(F, path);
  Rewrite(F);
  WriteLn(F, s);                 { the intrinsic, on a bare implicit-Self field }
  WriteLn(Self.F, s + '/self');  { ...and on the Self-qualified spelling }
  Close(F);
  Self.Write('member');          { the member is still reachable }
end;

function TLogger.ReadBack(const path: AnsiString): AnsiString;
var line: AnsiString;
begin
  System.Assign(F, path);
  Reset(F);
  Result := '';
  while not EOF(F) do
  begin
    ReadLn(F, line);
    Result := Result + '[' + line + ']';
  end;
  Close(F);
end;

function TLogger.ReadBackSelf(const path: AnsiString): AnsiString;
var line: AnsiString;
begin
  System.Assign(Self.F, path);
  Reset(Self.F);
  Result := '';
  while not EOF(Self.F) do
  begin
    ReadLn(Self.F, line);
    Result := Result + '<' + line + '>';
  end;
  Close(Self.F);
end;

function RecRoundTrip(const path: AnsiString): AnsiString;
var r: TRec; line: AnsiString;
begin
  System.Assign(r.F, path); Rewrite(r.F);
  WriteLn(r.F, 'rec one');
  WriteLn(r.F, 'rec two');
  Close(r.F);
  System.Assign(r.F, path); Reset(r.F);
  Result := '';
  while not EOF(r.F) do
  begin
    ReadLn(r.F, line);
    Result := Result + '(' + line + ')';
  end;
  Close(r.F);
end;

function VarRoundTrip(const path: AnsiString): AnsiString;
var g: Text; line: AnsiString;
begin
  System.Assign(g, path); Rewrite(g);
  WriteLn(g, 'var one');
  Write(g, 'var ');            { two writes, one line }
  WriteLn(g, 'two');
  Close(g);
  System.Assign(g, path); Reset(g);
  Result := '';
  while not EOF(g) do
  begin
    ReadLn(g, line);
    Result := Result + '{' + line + '}';
  end;
  Close(g);
end;

var
  dir, pa, pb, pc: AnsiString;
  lg: TLogger;
begin
  { TESTMGR_TMP FIRST. testmgr launches jobs through an environment ALLOWLIST
    (PXX_ / TESTMGR_ / LC_ / QEMU_ plus a fixed set), so TESTTMP alone does not
    reach the job -- the read returns empty and the fallback lands on the shared
    /tmp every concurrent job also writes, which is the collision the literal
    was replaced to avoid. TESTTMP second, because that is what
    `make test TESTTMP=$(mktemp -d)` exports. tools/testmgr_hardcoded_tmp_devtest.py }
  dir := GetEnvironmentVariable('TESTMGR_TMP');
  if dir = '' then dir := GetEnvironmentVariable('TESTTMP');
  if dir = '' then dir := '/tmp';
  pa := dir + '/test_text_field_a.txt';
  pb := dir + '/test_text_field_b.txt';
  pc := dir + '/test_text_field_c.txt';

  WriteLn('var    : ', VarRoundTrip(pa));
  WriteLn('record : ', RecRoundTrip(pb));

  lg := TLogger.Create;
  lg.Emit(pc, 'field line');
  WriteLn('field  : ', lg.ReadBack(pc));
  WriteLn('self   : ', lg.ReadBackSelf(pc));
  WriteLn('member : ', lg.Hits);

  DeleteFile(pa); DeleteFile(pb); DeleteFile(pc);
end.
