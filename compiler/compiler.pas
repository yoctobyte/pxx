{$mode objfpc}{$H+}
{ Pascal26 Compiler — hand-rolled recursive-descent, zero external deps }

program Pascal26;

uses SysUtils, BaseUnix;

{$include defs.inc}
{$include lexer.inc}
{$include clexer.inc}
{$include emit.inc}
{$include symtab.inc}
{$include parser.inc}
{$include codegen.inc}
{$include cparser.inc}
{$include elfwriter.inc}

{ ===== Main ===== }

var inFile, outFile: AnsiString; isC: Boolean; n: Integer;
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

  LoadFile(inFile, Source);
  if VERBOSE then writeln('Loaded file length: ', Length(Source));
  if not isC then
    ExpandIncludes(Source, GetFilePath(inFile));
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
  AddConst('StdErr', tyInteger, 2);

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
