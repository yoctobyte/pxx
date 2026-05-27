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
procedure CPreprocess(var src: AnsiString; const baseDir: AnsiString); forward;
{$include parser.inc}
{$include codegen.inc}
{$include cparser.inc}
{$include bparser.inc}
{$include elfwriter.inc}
{$include cpreproc.inc}

{ ===== Main ===== }

var inFile, outFile, option: AnsiString; isC, isBasic, readingOptions: Boolean; n, i: Integer;
begin
  DebugTrace := False;
  NoUnhandledHandler := False;
  PasInitDefines;
  i := 1;
  readingOptions := True;
  while (i <= ParamCount) and readingOptions do
  begin
    option := ParamStr(i);
    PasCommandOption := option;
    if option = '--debug' then
    begin
      DebugTrace := True;
      Inc(i);
    end
    else if option = '--strict-overload' then
    begin
      StrictOverload := True;
      Inc(i);
    end
    else if option = '--permissive-overload' then
    begin
      StrictOverload := False;
      Inc(i);
    end
    else if (option = '--no-unhandled-handler') or
            (option = '-fno-unhandled-handler') then
    begin
      NoUnhandledHandler := True;
      Inc(i);
    end
    else if (Length(option) > 2) and (option[1] = '-') and
            ((option[2] = 'd') or (option[2] = 'D')) then
    begin
      PasDefineCommandOption(3);
      Inc(i);
    end
    else if (Length(option) > 2) and (option[1] = '-') and
            ((option[2] = 'u') or (option[2] = 'U')) then
    begin
      PasUndefineCommandOption(3);
      Inc(i);
    end
    else if (Length(option) > 2) and (option[1] = '-') and
            ((option[2] = 'm') or (option[2] = 'M')) then
    begin
      { Dialect modes are accepted now; semantics remain the current objfpc-like subset. }
      if not PasObjFpcModeOption then
        begin writeln(StdErr, 'unsupported Pascal mode: ', option); Halt(1); end;
      Inc(i);
    end
    else if (Length(option) > 0) and (option[1] = '-') then
    begin
      writeln(StdErr, 'unknown option: ', option);
      Halt(1);
    end
    else
      readingOptions := False;
  end;
  if ParamCount < i then
    begin writeln(StdErr,'usage: pascal26/PXX [--debug] [-dNAME] [-uNAME] [-Mobjfpc] [--strict-overload] [--no-unhandled-handler] <src> [out]'); Halt(1); end;

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
  LoopNestDepth := 0; LoopBreakFixCount := 0; LoopContinueFixCount := 0;
  ExceptionParseDepth := 0; ExceptionCodegenDepth := 0;
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
    CPreprocess(Source, SourceFileDir);
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
