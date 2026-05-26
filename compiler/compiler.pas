{$mode objfpc}{$H+}
{ Pascal26 Compiler — hand-rolled recursive-descent, zero external deps }

program Pascal26;

uses SysUtils, BaseUnix;

{$include defs.inc}
{$include lexer.inc}
{$include clexer.inc}
{$include blexer.inc}
{$include emit.inc}
{$include symtab.inc}
{$include parser.inc}
{$include codegen.inc}
{$include cparser.inc}
{$include bparser.inc}
{$include elfwriter.inc}

{ ===== Main ===== }

var inFile, outFile: AnsiString; isC, isBasic: Boolean; n, i: Integer;
begin
  DebugTrace := False;
  i := 1;
  if ParamCount >= 1 then inFile := ParamStr(1);
  if (ParamCount >= 1) and (inFile = '--debug') then
  begin
    DebugTrace := True;
    i := 2;
  end;
  if ParamCount < i then
    begin writeln(StdErr,'usage: pascal26 [--debug] <src> [out]'); Halt(1); end;

  inFile  := ParamStr(i);
{$ifdef FPC}
  outFile := ChangeFileExt(inFile,'');
{$else}
  outFile := inFile;
{$endif}
  if ParamCount >= i + 1 then outFile := ParamStr(i + 1);

  n := Length(inFile);
  isC := (n >= 2) and (inFile[n] = 'c') and (inFile[n-1] = '.');
  isBasic := (n >= 4) and (inFile[n] = 's') and (inFile[n-1] = 'a') and (inFile[n-2] = 'b') and (inFile[n-3] = '.');

  LoadFile(inFile, Source);
  if DebugTrace then writeln('Loaded file length: ', Length(Source));
  SourceFileDir := GetFilePath(inFile);
  CompiledUnitCount := 0;
  InInterface := False;
  if (not isC) and (not isBasic) then
    ExpandIncludes(Source, SourceFileDir);
  if DebugTrace then writeln('After include expansion: ', Length(Source));

  SrcPos   := 1; SrcLine  := 1;
  CodeLen  := 0;
  DataLen  := STR_INIT_OFFSET;
  Data[MINUS_OFFSET]   := Ord('-');
  Data[NEWLINE_OFFSET] := 10;
  BSSSize  := 0;
  StrCount := 0; FixCount := 0;
  GlobFixCount := 0; CallFixCount := 0;
  SymCount := 0; ProcCount := 0;
  ExternalCount := 0; DynCallCount := 0; CurrentCLibrary := '';
  FrameSize := 0; CurProc := -1;
  TokCount := 0; TokPos := 0; TokCharLen := 0;
  MainProgramTokCount := MAX_TOKENS;
  BLabelCount := 0;
  BFixupCount := 0;
  ASTNodeCount := 0; CurASTNode := -1;
  UClsCount := 0; UFldCount := 0; UMthCount := 0; CurSelfClass := REC_NONE;
  AddConst('StdErr', tyInteger, 2);

  if isBasic then
  begin
    BLexAll(True);
    MainProgramTokCount := TokCount;
    TokPos := 0;
    Next;
    ParseBProgram;
  end
  else if isC then
  begin
    CLexAll;
    TokPos := 0;
    Next;
    ParseCProgram;
  end
  else
  begin
    LexAll;
    TokPos := 0;
    Next;
    ParseProgram;
  end;
  writeELF(outFile);

  writeln('ok: ',outFile,'  [code=',CodeLen,'B  data=',DataLen,
          'B  bss=',BSSSize,'B  procs=',ProcCount,']');
end.
