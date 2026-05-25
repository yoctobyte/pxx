{$mode objfpc}{$H+}
{ Pascal26 Compiler — hand-rolled recursive-descent, zero external deps }

program Pascal26;

uses SysUtils, BaseUnix;

{$include defs.inc}
{$include lexer.inc}
{$include emit.inc}
{$include symtab.inc}
{$include parser.inc}
{$include elfwriter.inc}

{ ===== Main ===== }

var inFile, outFile: AnsiString;
begin
  if ParamCount < 1 then
    begin writeln(StdErr,'usage: pascal26 <src.pas> [out]'); Halt(1); end;

  inFile  := ParamStr(1);
{$ifdef FPC}
  outFile := ChangeFileExt(inFile,'');
{$else}
  outFile := inFile;
{$endif}
  if ParamCount >= 2 then outFile := ParamStr(2);

  LoadFile(inFile, Source);
  writeln('Loaded file length: ', Length(Source));

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
  AddConst('StdErr', tyInteger, 2);

  Next;
  ParseProgram;
  writeELF(outFile);

  writeln('ok: ',outFile,'  [code=',CodeLen,'B  data=',DataLen,
          'B  bss=',BSSSize,'B  procs=',ProcCount,']');
end.
