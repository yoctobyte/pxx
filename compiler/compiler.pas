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
{$include elfwriter.inc}

{ ===== Main ===== }

var inFile, outFile: AnsiString; isC, isBasic: Boolean; n, i: Integer;
begin
  if ParamCount < 1 then
    begin writeln(StdErr,'usage: pascal26 <src> [out]'); Halt(1); end;

  inFile  := ParamStr(1);
{$ifdef FPC}
  outFile := ChangeFileExt(inFile,'');
{$else}
  outFile := inFile;
{$endif}
  if ParamCount >= 2 then outFile := ParamStr(2);

  n := Length(inFile);
  isC := (n >= 2) and (inFile[n] = 'c') and (inFile[n-1] = '.');
  isBasic := (n >= 4) and (inFile[n] = 's') and (inFile[n-1] = 'a') and (inFile[n-2] = 'b') and (inFile[n-3] = '.');

  LoadFile(inFile, Source);
  if VERBOSE then writeln('Loaded file length: ', Length(Source));
  SourceFileDir := GetFilePath(inFile);
  CompiledUnitCount := 0;
  InInterface := False;
  if (not isC) and (not isBasic) then
    ExpandIncludes(Source, SourceFileDir);
  if VERBOSE then writeln('After include expansion: ', Length(Source));

  SrcPos   := 1; SrcLine  := 1;
  CodeLen  := 0;
  DataLen  := STR_INIT_OFFSET;
  Data[MINUS_OFFSET]   := Ord('-');
  Data[NEWLINE_OFFSET] := 10;
  BSSSize  := 0;
  StrCount := 0; FixCount := 0;
  GlobFixCount := 0; CallFixCount := 0;
  SymCount := 0; ProcCount := 0;
  FrameSize := 0; CurProc := -1;
  TokCount := 0; TokPos := 0; TokCharLen := 0;
  ASTNodeCount := 0; CurASTNode := -1;
  UClsCount := 0; UFldCount := 0; UMthCount := 0; CurSelfClass := REC_NONE;
  AddConst('StdErr', tyInteger, 2);

  if isBasic then
  begin
    BLexAll(True);
    writeln('--- BASIC Token Dump (Proof of Concept) ---');
    for n := 0 to TokCount - 1 do
    begin
      write('Token ', n, ': Kind=', Ord(Tokens[n].Kind), ' Line=', Tokens[n].Line);
      if Tokens[n].SLen > 0 then
      begin
        write(' SVal=');
        for i := 0 to Tokens[n].SLen - 1 do
          write(TokChars[Tokens[n].SOffset + i]);
      end;
      if Tokens[n].Kind = tkInteger then
        write(' IVal=', Tokens[n].IVal);
      writeln;
    end;
    writeln('------------------------------------------');
    Exit;
  end;

  if isC then
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
