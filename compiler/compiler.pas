{$mode objfpc}{$H+}
{ Pascal26 Compiler — hand-rolled recursive-descent, zero external deps }

program Pascal26;

{ The compiler is written case-sensitively and relies on it (identifiers that
  differ only in case, speculative FindProc/FindSym lookups). User .pas defaults
  to case-insensitive; we opt in. }
{$CASESENSITIVE ON}
{$NESTEDCOMMENTS ON}

uses SysUtils, BaseUnix;

{$include defs.inc}
{$include lexer.inc}
{$include clexer.inc}
{$include blexer.inc}
{$include pylexer.inc}
{$include emit.inc}
{$include symtab.inc}
{$include exception_emit.inc}
{$include asmenc.inc}
procedure CPreprocess(var src: AnsiString; const baseDir: AnsiString); forward;
{$include parser.inc}
{$include ir.inc}
function GetOrAllocSymRTTI(symIdx: Integer): Integer; forward;
{$include ir_codegen_aarch64.inc}
{$include ir_codegen386.inc}
{$include ir_codegen_arm32.inc}
{$include ir_codegen.inc}
{$include cparser.inc}
{$include bparser.inc}
{$include pyparser.inc}
{$include elfwriter.inc}
{$include rtti_emit.inc}
{$include resources_emit.inc}
{$include cpreproc.inc}

{ ===== Main ===== }

var inFile, outFile, option, exePath: AnsiString; readingOptions: Boolean; n, i, j: Integer;
begin
  DebugTrace := False;
  DumpIR := False;
  DumpRTTI := False;
  TargetArch := TARGET_X86_64;
  TARGET_PTR_SIZE := 8;
  NoUnhandledHandler := False;
  ThreadSafeMode := False;
  EnableAutoVar := True;
  EnableLazyVar := True;
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
    else if option = '--dump-ir' then
    begin
      DumpIR := True;
      Inc(i);
    end
    else if option = '--dump-rtti' then
    begin
      DumpRTTI := True;
      Inc(i);
    end
    else if option = '--experimental-ir-codegen' then
    begin
      { Deprecated no-op: IR is the only backend. Accepted for compatibility. }
      Inc(i);
    end
    else if option = '--target=x86_64' then
    begin
      TargetArch := TARGET_X86_64;
      Inc(i);
    end
    else if option = '--target=i386' then
    begin
      TargetArch := TARGET_I386;
      Inc(i);
    end
    else if option = '--target=aarch64' then
    begin
      TargetArch := TARGET_AARCH64;
      Inc(i);
    end
    else if option = '--target=arm32' then
    begin
      TargetArch := TARGET_ARM32;
      Inc(i);
    end
    else if option = '--strict-overload' then
    begin
      StrictOverload := True;
      Inc(i);
    end
    else if option = '--threadsafe' then
    begin
      ThreadSafeMode := True;
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
    else if (option = '--no-auto-var') or
            (option = '-fno-auto-var') then
    begin
      EnableAutoVar := False;
      Inc(i);
    end
    else if (option = '--no-lazy-var') or
            (option = '-fno-lazy-var') then
    begin
      EnableLazyVar := False;
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
  if (TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) then
    TARGET_PTR_SIZE := 4
  else
    TARGET_PTR_SIZE := 8;
  PasApplyTargetDefines;
  if ParamCount < i then
    begin writeln(StdErr,'usage: pascal26/PXX [--debug] [--dump-ir] [-dNAME] [-uNAME] [-Mobjfpc] [--strict-overload] [--no-unhandled-handler] <src> [out]'); Halt(1); end;

  inFile  := ParamStr(i);
{$ifdef FPC}
  outFile := ChangeFileExt(inFile,'');
{$else}
  { Default output = input path with the extension stripped (foo.lpr -> foo).
    Never the input itself — that overwrote the source with the binary. }
  outFile := GetFilePath(inFile) + GetFileBaseName(inFile);
{$endif}
  if ParamCount >= i + 1 then outFile := ParamStr(i + 1);
  { Last-resort guard: refuse to write the binary over the source file. }
  if outFile = inFile then outFile := inFile + '.out';

  n := Length(inFile);
  isC := (n >= 2) and (inFile[n] = 'c') and (inFile[n-1] = '.');
  isBasic := (n >= 4) and (inFile[n] = 's') and (inFile[n-1] = 'a') and (inFile[n-2] = 'b') and (inFile[n-3] = '.');
  isNilPy := (n >= 4) and (inFile[n] = 'y') and (inFile[n-1] = 'p') and (inFile[n-2] = 'n') and (inFile[n-3] = '.');

  LoadFile(inFile, Source);
  if DebugTrace then writeln('Loaded file length: ', Length(Source));
  SourceFileDir := GetFilePath(inFile);
  CurUnitDir := SourceFileDir;
  CurSrcBaseName := GetFileBaseName(inFile);
  exePath := ParamStr(0);              { copy to a local; ParamStr result does not match the param overload directly }
  ExeDir := GetFilePath(exePath);
  CompiledUnitCount := 0;
  InitProcCount := 0;
  InInterface := False;
  if (not isC) and (not isBasic) and (not isNilPy) then
    ExpandIncludes(Source, SourceFileDir);
  if DebugTrace then writeln('After include expansion: ', Length(Source));

  SrcPos   := 1; SrcLine  := 1;
  CurTok.Line := 1;
  ValidateBuiltinRecordLayout;
  CodeLen  := 0;
  DataLen      := STR_INIT_OFFSET;
  SpacesOffset := -1;
  Data[MINUS_OFFSET]   := Ord('-');
  Data[NEWLINE_OFFSET] := 10;
  BSSSize  := 0;
  StrCount := 0; FixCount := 0;
  GlobFixCount := 0; CallFixCount := 0; ProcAddrFixCount := 0;
  SymCount := 0; ProcCount := 0;
  CurrentUnitIdx := -1;
  CTypedefCount := 0;
  CTypedefCharLen := 0;
  ExternalCount := 0; DynCallCount := 0; CurrentCLibrary := '';
  FrameSize := 0; CurProc := -1;
  TokCount := 0; TokPos := 0; TokCharLen := 0;
  MainProgramTokCount := MAX_TOKENS;
  BLabelCount := 0;
  BFixupCount := 0;
  ASTNodeCount := 0; CurASTNode := -1;
  IRCount := 0; IRLabelCount := 0;
  LoopNestDepth := 0; LoopBreakFixCount := 0; LoopContinueFixCount := 0;
  ExceptionCodegenDepth := 0; ExceptionHandlerParseDepth := 0; WithStackDepth := 0; AsmBytesCount := 0;
  InLValueWrite := False;
  UClsCount := 0; UFldCount := 0; UMthCount := 0; CurSelfClass := REC_NONE;
  MethodFixCount := 0; UPropCount := 0;
  DataPtrFixCount := 0;
  RTTIRegistryOff := -1; RTTIRegistryCount := 0;
  AnonDynArrayCount := 0;
  ResPendCount := 0; ResourceTableOff := -1; ResourceCount := 0;
  EnumTypeCount := 0; EnumValCount := 0; LastTypeEnumId := -1;
  AliasCount := 0;
  AddConst('StdErr', tyInteger, 2);

  if isNilPy then
  begin
    PyLexAll(False);
    MainProgramTokCount := TokCount;
    TokPos := 0;
    Next;
    ParsePyProgram;
  end
  else if isBasic then
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
  if (not isC) and (not isBasic) and (not isNilPy) then
  begin
    EmitRTTI;
    if DumpRTTI then DumpRTTITables;
    EmitResources;
  end;
  { Patch RTTIRegistryOff (-100) and ResourceTableOff (-101) relocations. A
    sentinel with no table is dropped (the intrinsic then returns nil/0). }
  i := 0;
  while i < FixCount do
  begin
    if Fixups[i].DataOff = -100 then
    begin
      if RTTIRegistryOff >= 0 then
        Fixups[i].DataOff := RTTIRegistryOff
      else
      begin
        for j := i to FixCount - 2 do
          Fixups[j] := Fixups[j + 1];
        Dec(FixCount);
        continue;
      end;
    end
    else if Fixups[i].DataOff = -101 then
    begin
      if ResourceTableOff >= 0 then
        Fixups[i].DataOff := ResourceTableOff
      else
      begin
        for j := i to FixCount - 2 do
          Fixups[j] := Fixups[j + 1];
        Dec(FixCount);
        continue;
      end;
    end
    else if (Fixups[i].DataOff <= -RECORD_RTTI_DATAREF_BASE) and (Fixups[i].DataOff > -SYM_RTTI_DATAREF_BASE) then
    begin
      j := -Fixups[i].DataOff - RECORD_RTTI_DATAREF_BASE;
      if (j >= 0) and (j < UClsCount) and (UClsRTTIOff[j] >= 0) then
        Fixups[i].DataOff := UClsRTTIOff[j]
      else
        Error('record reference to a record with no RTTI');
    end

    else if Fixups[i].DataOff <= -CLASSREF_DATAREF_BASE then
    begin
      { class-reference (metaclass) value: resolve to the class's RTTI blob. }
      j := -Fixups[i].DataOff - CLASSREF_DATAREF_BASE;   { recover class index ci }
      if (j >= 0) and (j < UClsCount) and (UClsRTTIOff[j] >= 0) then
        Fixups[i].DataOff := UClsRTTIOff[j]
      else
        Error('class reference to a class with no RTTI (no published members?)');
    end;
    Inc(i);
  end;
  for i := 0 to ProcCount - 1 do
    writeln('proc ', i, ': ', Procs[i].Name, ' at ', Procs[i].BodyAddr);
  if (TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) then
    writeELF32(outFile)
  else
    writeELF(outFile);

  writeln('ok: ',outFile,'  [code=',CodeLen,'B  data=',DataLen,
          'B  bss=',BSSSize,'B  procs=',ProcCount,']');
end.
