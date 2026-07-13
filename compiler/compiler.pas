{ SPDX-License-Identifier: MPL-2.0 }
{$mode objfpc}{$H+}
{ Pascal26 Compiler — hand-rolled recursive-descent, zero external deps }

program Pascal26;

{ The compiler is written case-sensitively and relies on it (identifiers that
  differ only in case, speculative FindProc/FindSym lookups). User .pas defaults
  to case-insensitive; we opt in. }
{$CASESENSITIVE ON}
{$NESTEDCOMMENTS ON}

{ The compiler relies on builtins only and must not pull the default
  standard-unit surface (textfile drags the PAL platform_backend onto a search
  path the bootstrap does not provide). This define opts out, the same as the
  --no-default-rtl flag; it travels with the source so every self-build path
  (bootstrap, cross-bootstrap, stabilize, manual) is covered. Harmless under
  real FPC (the logic that reads it is PXX-only). }
{$define PXX_NODEFAULTRTL}

{ Real FPC only: the FPC-seeded bootstrap pulls SysUtils/BaseUnix. Under PXX
  self-host these were always a no-op (builtins cover what little is used), and
  must stay unloaded now that `uses sysutils` can resolve a real
  lib/rtl/sysutils.pas — the compiler must not drag a user RTL unit into its own
  build. {$ifdef FPC} is true only under real FPC (never under PXX). }
{ asmcore (lib/asmcore) is compiled INTO the compiler so the .asm frontend can
  encode through the real library (feature-asm-mvp-frontend). Both real FPC
  (the bootstrap) and PXX self-host process this uses; only the SysUtils/
  BaseUnix host shims are FPC-only. {$UNITPATH} makes the FPC side find
  lib/asmcore with no -Fu flag needed -- "self-host when pointed to the
  right source, dependencies implicit" (PXX never needed the flag: its own
  ParseUsesUnit already resolves lib/asmcore via the same exe-anchored
  search chain as lib/rtl/lib/pcl, see compiler/parser.inc; {$UNITPATH} is
  an FPC-only directive, silently ignored by PXX like any other directive
  it doesn't recognize). Path is relative to this source file's own
  directory (compiler/), not CWD -- portable to any checkout location. }
{$UNITPATH ../lib/asmcore}
{$ifdef FPC}
uses SysUtils, BaseUnix, asmcore_base, asmcore_x64;
{$else}
uses asmcore_base, asmcore_x64;
{$endif}

{$include defs.inc}
{$include zdefs.inc}
{$include lexer.inc}
{$include clexer.inc}
{$include blexer.inc}
{$include pylexer.inc}
{$include rlexer.inc}
{$include alexer.inc}
{$include zlexer.inc}
{$include llexer.inc}
{$include flexer.inc}
{$include glexer.inc}
{$include elexer.inc}
{$include emit.inc}
procedure AsmB(b: Integer); forward;
procedure AsmI16(v: Int64); forward;
procedure AsmI32(v: Int64); forward;
procedure AsmI64(v: Int64); forward;
{$include x64enc.inc}
{$include rv32enc.inc}
{$include xtensaenc.inc}
{ Forward decls needed by the single-pass FPC seed (and --require-forward).
  PXX_NEED_FORWARDS := FPC or PXX_REQUIRE_FORWARD. PXX without it prescans and
  skips this; placed before symtab.inc so it is above every use it covers. }
{$ifdef FPC}{$define PXX_NEED_FORWARDS}{$endif}
{$ifdef PXX_REQUIRE_FORWARD}{$define PXX_NEED_FORWARDS}{$endif}
{$ifdef PXX_NEED_FORWARDS}{$include forwards.inc}{$endif}
{$include symtab.inc}
{$include exception_emit.inc}
{$include coroutine_emit.inc}
{$include thread_emit.inc}
{$include asmenc.inc}
{$include asmtext.inc}
{$include asmtext_386.inc}
{$include asmtext_rv32.inc}
{$include asmtext_a64.inc}
{$include asmtext_arm32.inc}
{$include asmtext_xtensa.inc}
procedure CPreprocess(var src: AnsiString; const baseDir: AnsiString); forward;
{$include parser.inc}
{$include ir.inc}
function GetOrAllocSymRTTI(symIdx: Integer): Integer; forward;
function GetOrAllocNodeDynDesc(node: Integer): Integer; forward;
function GetOrAllocDynUniqueDesc(node: Integer): Integer; forward;
{$include ir_codegen_aarch64.inc}
{$include ir_codegen386.inc}
{$include ir_codegen_arm32.inc}
{$include ir_codegen_riscv32.inc}
{$include ir_codegen_xtensa.inc}
{$include ir_codegen.inc}
{$include asmdisasm_x64.inc}
{$include cparser.inc}
{$include bparser.inc}
{$include pyparser.inc}
{$include rparser.inc}
{$include aparser.inc}
{$include zparser.inc}
{$include lparser.inc}
{$include wparser.inc}
{$include fparser.inc}
{$include gparser.inc}
{$include eparser.inc}
{$include elfwriter.inc}
{$include rtti_emit.inc}
{$include resources_emit.inc}
{$include cpreproc.inc}
{$include asmfront.inc}

{ ===== Main ===== }

var inFile, outFile, option, exePath: AnsiString; readingOptions: Boolean; n, i, j: Integer;
begin
  DebugTrace := False;
  DebugInfo := False;
  DbgMainTokEnd := MAX_TOKENS;
  DumpIR := False;
  DumpProcMap := False;
  MeasureRegcall := False;
  RegcallProcsWithParams := 0;
  RegcallTotalParams := 0;
  RegcallEligibleParams := 0;
  RegcallAddrTaken := 0;
  RegcallCapped2 := 0;
  RegcallCapped5 := 0;
  RegcallEligibleUses := 0;
  MeasureInline := False;
  InlineASTNext := INLINE_AST_BASE;
  InliningActive := 0;
  OptLevel := 2;   { -O2 is the default (feature-optimization-levels): ~1.34x faster / ~11% smaller, self-host -O2 fixedpoint byte-identical. -O0 is still selectable and remains the byte-identity reference; opt passes gate on OptLevel>=tier. }
  OptLevelExplicit := False;
  RcSuppressAssign := False;
  WarnedMissedFold := False;
  WarnMissedFold := False;
  DumpCpp := False;
  NoStdInc := False;
  CUseSystemLibs := False;
  CSystemLibCount := 0;
  CrtlSrcPulledCount := 0;
  WarnSelfResult := False;
  DumpRTTI := False;
  TargetArch := TARGET_X86_64;
  XtensaABI := XTENSA_ABI_CALL0;
  XtensaSoftDivide := False;
  XtensaHasFpu := False;
  XtensaFastDoubles := False;
  TARGET_PTR_SIZE := 8;
  EmitObjMode := False;
  EmitSharedMode := False;
  EmitAsmTextMode := False;
  EspBareBoot := False;
  NoDefaultRtl := False;
  StrictIR := True;   { DEFAULT ON since 2026-07-11: IRVerify rejects any IR_UNSUPPORTED
                        node (frontend failed to lower an AST node) — fail loud instead of
                        the silent self-host miscompile it once caused. All frontends incl.
                        the Rust suite measure 0. --no-strict-ir opts out for in-development
                        frontend work. feature-selfhost-guard-ir-unsupported. }
  TargetPlatform := PLATFORM_POSIX;
  PlatformExplicit := False;
  NoUnhandledHandler := False;
  ThreadSafeMode := False;
  ProcExceptionCleanupFrameActive := False;
  EnableAutoVar := True;
  EnableLazyVar := True;
  CIncludeDirCount := 0;
  PasUnitDirCount := 0;
  PasIncDirCount := 0;
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
    else if option = '--proc-map' then
    begin
      DumpProcMap := True;
      Inc(i);
    end
    else if option = '--measure-regcall' then
    begin
      MeasureRegcall := True;
      Inc(i);
    end
    else if option = '--measure-inline' then
    begin
      MeasureInline := True;
      Inc(i);
    end
    else if option = '--warn-missed-fold' then
    begin
      WarnMissedFold := True;
      Inc(i);
    end
    else if (option = '-O0') or (option = '-O1') or (option = '-O2') or (option = '-O3') then
    begin
      OptLevel := Ord(option[3]) - Ord('0');
      OptLevelExplicit := True;
      Inc(i);
    end
    else if option = '--dump-cpp' then
    begin
      DumpCpp := True;
      Inc(i);
    end
    else if option = '--system-libs' then
    begin
      { Opt out of the libc-free crtl auto-pull: resolve C library functions as
        real shared-library externs (DT_NEEDED libc/libm) instead, the way a
        normal toolchain links them. }
      CUseSystemLibs := True;
      Inc(i);
    end
    else if (Length(option) > 14) and
            (option[1] = '-') and (option[2] = '-') and
            (option[3] = 's') and (option[4] = 'y') and
            (option[5] = 's') and (option[6] = 't') and
            (option[7] = 'e') and (option[8] = 'm') and
            (option[9] = '-') and (option[10] = 'l') and
            (option[11] = 'i') and (option[12] = 'b') and
            (option[13] = 's') and (option[14] = '=') then
    begin
      { Granular opt-out: only the listed soname stems use real system shared
        libraries; every other crtl header keeps the bundled libc-free impl. }
      AddCSystemLibSpec(PasOptionTail(option, 15));
      Inc(i);
    end
    else if (option = '-nostdinc') or (option = '--nostdinc') then
    begin
      NoStdInc := True;
      Inc(i);
    end
    else if option = '-g' then
    begin
      { DWARF Tier 1: emit .debug_line + a minimal CU stub (x86-64 only).
        Off by default → self-host / bootstrap byte-identical path untouched. }
      DebugInfo := True;
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
    else if option = '--target=xtensa' then
    begin
      TargetArch := TARGET_XTENSA;
      Inc(i);
    end
    else if option = '--platform=posix' then
    begin
      TargetPlatform := PLATFORM_POSIX;
      PlatformExplicit := True;
      Inc(i);
    end
    else if option = '--platform=esp' then
    begin
      TargetPlatform := PLATFORM_ESP;
      PlatformExplicit := True;
      Inc(i);
    end
    else if option = '--xtensa-abi=call0' then
    begin
      XtensaABI := XTENSA_ABI_CALL0;
      Inc(i);
    end
    else if option = '--xtensa-abi=windowed' then
    begin
      XtensaABI := XTENSA_ABI_WINDOWED;
      Inc(i);
    end
    else if (option = '--xtensa-cpu=lx6') or (option = '--xtensa-soft-divide') then
    begin
      { ESP32 classic (LX6): no hardware divide option. Route div/mod through
        the software shift-subtract helpers. }
      XtensaSoftDivide := True;
      Inc(i);
    end
    else if option = '--xtensa-fpu' then
    begin
      { ESP32 / ESP32-S3: single-precision hardware FPU present. Lower single
        +,-,* to add.s/sub.s/mul.s. NOT for ESP32-S2 (no FPU). }
      XtensaHasFpu := True;
      Inc(i);
    end
    else if option = '--target=riscv32' then
    begin
      TargetArch := TARGET_RISCV32;
      Inc(i);
    end
    else if option = '--emit-obj' then
    begin
      EmitObjMode := True;
      Inc(i);
    end
    else if option = '--shared' then
    begin
      { .asm frontend only (feature-asm-source-frontend task #6): x86-64
        ET_DYN shared-library output. }
      EmitSharedMode := True;
      Inc(i);
    end
    else if option = '-S' then
    begin
      { head 2 (feature-asm-textual-emit-mode): also write <out>.s, a best-
        effort x86-64 disassembly of whatever codegen just produced -- any
        source language, x86-64 only. Additive: the normal binary output
        (ET_EXEC/-c/--shared, whichever else was requested) still happens. }
      EmitAsmTextMode := True;
      Inc(i);
    end
    else if option = '--esp-profile=bare' then
    begin
      { Bare-metal ESP32 image: SoC SRAM map, sp-init startup, UART MMIO output,
        no ESP-IDF. Linked ET_EXEC (do NOT set EmitObjMode). xtensa/riscv32. }
      EspBareBoot := True;
      Inc(i);
    end
    else if option = '--no-default-rtl' then
    begin
      { Opt out of the default standard-unit surface (textfile + builtin).
        Used by the compiler self-build, which must not pull PAL units. }
      NoDefaultRtl := True;
      Inc(i);
    end
    else if (option = '--werror') or (option = '-Werror') then
    begin
      { Promote any compiler-emitted warning to a fatal error. }
      WarnAsError := True;
      Inc(i);
    end
    else if PasOptHasPrefix(option, '--max-stack-frame=') then
    begin
      { Tune (or disable with =0) the oversized-stack-frame warning threshold in
        bytes. Default MAX_STACK_FRAME_SIZE. See feature-warn-oversized-stack-frame. }
      MaxStackFrameSize := PasOptionInt(option, 19);
      Inc(i);
    end
    else if option = '--no-signals' then
    begin
      { Opt out of the default signal runtime (SIGINT/SIGTERM graceful dispatch
        + SetSignalHandler). Default on for PC targets; see
        feature-signal-handlers. }
      NoSignals := True;
      Inc(i);
    end
    else if option = '--no-div-check' then
    begin
      { Opt out of the integer div/mod pre-divide zero check (default on, FPC
        style: divide by zero = clean "Runtime error 200" instead of a raw
        SIGFPE core dump). See bug-integer-div-zero-sigfpe-uncatchable. }
      NoDivCheck := True;
      Inc(i);
    end
    else if option = '--strict-ir' then
    begin
      { Now the default; kept as an accepted no-op for existing invocations. }
      StrictIR := True;
      Inc(i);
    end
    else if option = '--no-strict-ir' then
    begin
      { Opt OUT of the self-host safety guard (IRVerify hard-error on any
        IR_UNSUPPORTED node) — for an in-development frontend that still
        emits it for unlowered constructs. See
        feature-selfhost-guard-ir-unsupported. }
      StrictIR := False;
      Inc(i);
    end
    else if option = '--auto-locals' then
    begin
      { Opt in to implicit (sloppy) locals: assignment to a previously-undeclared
        name declares a routine-local tyAuto var (type inferred from the RHS)
        instead of erroring. Off by default (masks typos). Equivalent to
        {$IMPLICITVARS ON}. See feature-implicit-locals-sloppy-switch. }
      ImplicitVars := True;
      Inc(i);
    end
    else if option = '--lax-decl-order' then
    begin
      { Opt out of declare-before-use gating for forward-visible global vars
        (strict/FPC-parity is the default). Restores the old lenient behavior.
        Equivalent to {$DECLORDER OFF}. }
      LaxDeclOrder := True;
      Inc(i);
    end
    else if option = '--warn-self-result' then
    begin
      { Warn when a parameterless function's bare own name is read as a value
        (FPC reads its Result; a recursive-descent author usually meant Name()).
        Opt-in: the compiler's own source uses the bare-name=Result idiom. }
      WarnSelfResult := True;
      Inc(i);
    end
    else if option = '--strict-overload' then
    begin
      StrictOverload := True;
      Inc(i);
    end
    else if option = '--strict-case' then
    begin
      { FPC-parity case-label diagnostics (inverted ranges, duplicate/
        overlapping labels). PXX's lax default keeps first-match semantics. }
      StrictCase := True;
      Inc(i);
    end
    else if option = '--threadsafe' then
    begin
      ThreadSafeMode := True;
      Inc(i);
    end
    else if option = '--mimic-fpc' then
    begin
      MimicFpc := True;
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
    else if (Length(option) > 3) and (option[1] = '-') and (option[2] = 'F') and (option[3] = 'u') then
    begin
      { -Fu<dir> (FPC-style): add a Pascal-unit (`uses`) search root only. }
      AddPasUnitDir(PasOptionTail(option, 4));
      Inc(i);
    end
    else if (Length(option) > 3) and (option[1] = '-') and (option[2] = 'F') and (option[3] = 'i') then
    begin
      { -Fi<dir> (FPC-style): add a {$I file} include search root. }
      AddPasIncDir(PasOptionTail(option, 4));
      Inc(i);
    end
    else if (Length(option) > 2) and (option[1] = '-') and (option[2] = 'I') then
    begin
      { -I<dir>: add a search root for BOTH C `#include` and Pascal `uses`
        (project / library dir), per feature-dynamic-include-paths-config. }
      AddCIncludeDir(PasOptionTail(option, 3));
      AddPasUnitDir(PasOptionTail(option, 3));
      Inc(i);
    end
    else if (Length(option) > 2) and (option[1] = '-') and
            ((option[2] = 'd') or (option[2] = 'D')) then
    begin
      PasDefineCommandOption(3);
      { Also capture for the C preprocessor (raw, may carry `=value`). }
      if CCmdDefCount < MAX_C_CMD_DEFINES then
      begin
        CCmdDefRaw[CCmdDefCount] := PasOptionTail(option, 3);
        Inc(CCmdDefCount);
      end;
      Inc(i);
    end
    else if (Length(option) > 2) and (option[1] = '-') and
            ((option[2] = 'u') or (option[2] = 'U')) then
    begin
      PasUndefineCommandOption(3);
      if CCmdUndefCount < MAX_C_CMD_DEFINES then
      begin
        CCmdUndefRaw[CCmdUndefCount] := PasOptionTail(option, 3);
        Inc(CCmdUndefCount);
      end;
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
  if (TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) or
     (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
    TARGET_PTR_SIZE := 4
  else
    TARGET_PTR_SIZE := 8;
  if EspBareBoot and (TargetArch <> TARGET_RISCV32) and (TargetArch <> TARGET_XTENSA) then
  begin writeln(StdErr, '--esp-profile=bare requires --target=riscv32 (esp32c3) or --target=xtensa (esp32s3)'); Halt(1); end;
  { The thread-safe runtime (heap/ARC locks, statement-atomic I/O) exists on
    x86-64 (hand-emitted lock blobs) and i386 (Pascal softlock in builtinheap
    via PXX_TS_SOFTLOCK + the 386 I/O lock stubs); on other targets
    --threadsafe would silently emit an UNLOCKED runtime. Fail clearly instead
    (feature-threadsafe-heap-contract / feature-i386-threadsafe-locks). }
  if ThreadSafeMode and (TargetArch <> TARGET_X86_64) and (TargetArch <> TARGET_I386)
     and (TargetArch <> TARGET_AARCH64) and (TargetArch <> TARGET_ARM32) then
  begin writeln(StdErr, '--threadsafe is x86-64/i386/aarch64/arm32 only: the heap/ARC/I-O locks are not implemented on this target yet'); Halt(1); end;
  if EspBareBoot and (TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_WINDOWED) then
  begin writeln(StdErr, '--esp-profile=bare on xtensa requires Call0 (omit --xtensa-abi=windowed): the windowed ABI needs window-overflow exception handlers + vecbase that bare-metal does not install'); Halt(1); end;
  { Derive the platform from the target unless --platform= set it explicitly.
    esp targets (xtensa/riscv32) and bare-metal profiles are esp; all else is
    posix. The platform axis stays independent: an explicit --platform overrides
    this (e.g. a hosted RTOS on xtensa later). }
  if not PlatformExplicit then
  begin
    { riscv32 is dual-role: bare ESP32-C3 (--esp-profile=bare) OR hosted linux
      (qemu-user) — only the bare profile is esp. xtensa has no hosted leg. }
    if EspBareBoot or (TargetArch = TARGET_XTENSA) then
      TargetPlatform := PLATFORM_ESP
    else
      TargetPlatform := PLATFORM_POSIX;
  end;
  PasApplyTargetDefines;
  PasApplyPlatformDefines;
  if MimicFpc then PasApplyMimicDefines;
  { -g (DWARF Tier-1) implies -O0 unless the user explicitly chose an -O level:
    opt passes (inline, DCE, jump threading) relocate/elide source lines and small
    functions, so breakpoints and single-step break. `-g -O2` is still honoured for
    users who accept degraded debug info. See feature-optimization-levels. }
  if DebugInfo and not OptLevelExplicit then OptLevel := 0;
  if ParamCount < i then
    begin writeln(StdErr,'usage: pascal26/PXX [--debug] [--dump-ir] [-dNAME] [-uNAME] [-Mobjfpc] [--strict-overload] [--strict-case] [--no-unhandled-handler] <src> [out]'); Halt(1); end;

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
  { A .o output name implies object emission (same as --emit-obj). }
  n := Length(outFile);
  if (n >= 2) and (outFile[n] = 'o') and (outFile[n-1] = '.') then
    EmitObjMode := True;
  { A .so output name implies shared-library emission (same as --shared). }
  if (n >= 3) and (outFile[n] = 'o') and (outFile[n-1] = 's') and (outFile[n-2] = '.') then
    EmitSharedMode := True;

  n := Length(inFile);
  isC := (n >= 2) and (inFile[n] = 'c') and (inFile[n-1] = '.');
  isBasic := (n >= 4) and (inFile[n] = 's') and (inFile[n-1] = 'a') and (inFile[n-2] = 'b') and (inFile[n-3] = '.');
  isNilPy := (n >= 4) and (inFile[n] = 'y') and (inFile[n-1] = 'p') and (inFile[n-2] = 'n') and (inFile[n-3] = '.');
  isAsm := (n >= 4) and (inFile[n] = 'm') and (inFile[n-1] = 's') and (inFile[n-2] = 'a') and (inFile[n-3] = '.');
  isRust := (n >= 3) and (inFile[n] = 's') and (inFile[n-1] = 'r') and (inFile[n-2] = '.');
  isAda := (n >= 4) and (inFile[n] = 'b') and (inFile[n-1] = 'd') and (inFile[n-2] = 'a') and (inFile[n-3] = '.');
  isZig := (n >= 4) and (inFile[n] = 'g') and (inFile[n-1] = 'i') and (inFile[n-2] = 'z') and (inFile[n-3] = '.');
  isLol := (n >= 4) and (inFile[n] = 'l') and (inFile[n-1] = 'o') and (inFile[n-2] = 'l') and (inFile[n-3] = '.');
  isWs := (n >= 3) and (inFile[n] = 's') and (inFile[n-1] = 'w') and (inFile[n-2] = '.');
  isF90 := (n >= 5) and (inFile[n] = '0') and (inFile[n-1] = '9') and (inFile[n-2] = 'f') and (inFile[n-3] = '.');
  isAlgol := (n >= 5) and (inFile[n] = 'g') and (inFile[n-1] = 'l') and (inFile[n-2] = 'a') and (inFile[n-3] = '.');
  isErl := (n >= 5) and (inFile[n] = 'l') and (inFile[n-1] = 'r') and (inFile[n-2] = 'e') and (inFile[n-3] = '.');

  LoadFile(inFile, Source);
  DbgSrcName := inFile;   { -g: file name recorded in .debug_line + CU DIE }
  if DebugTrace then writeln('Loaded file length: ', Length(Source));
  SourceFileDir := GetFilePath(inFile);
  CurUnitDir := SourceFileDir;
  CurSrcBaseName := GetFileBaseName(inFile);
  exePath := ParamStr(0);              { copy to a local; ParamStr result does not match the param overload directly }
  ExeDir := GetFilePath(exePath);
  { Default standard surface pulls textfile, which `uses platform` -> resolves
    platform_backend from the PAL dir. Anchor the POSIX backend dir to the
    compiler binary so a plain `pxx foo.pas` finds it with no -Fu. Appended
    last, so an explicit user -Fu (e.g. a per-platform override) still wins.
    ESP targets select their own backend and are excluded from default RTL. }
  if (not NoDefaultRtl) and (TargetArch <> TARGET_XTENSA) and
     ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
  begin
    { ExeDir-anchored (the installed layout: <root>/compiler/ -> ../lib/...) plus
      a CWD-relative fallback, mirroring ParseUsesUnit's own search chain. The
      latter covers the self-host tests, which run a /tmp copy of the compiler
      with CWD at the repo root, so ExeDir-relative ('/tmp/../lib/...') misses. }
    if ExeDir <> '' then
      AddPasUnitDir(ExeDir + '../lib/rtl/platform/posix/');
    AddPasUnitDir('lib/rtl/platform/posix/');
  end;
  { lib/asmcore resolution (asmcore_base/asmcore_x64, both for the compiler's
    own .asm frontend / inline-asm branches and for any user program) is now a
    first-class peer of RTL/PCL in ParseUsesUnit's own search chain — no
    AddPasUnitDir needed here, see compiler/parser.inc (asmdir). }
  CompiledUnitCount := 0;
  UnitAliasCount := 0;
  InitProcCount := 0;
  InInterface := False;
  PreScanPass := False;
  DeclItemCount := 0;
  if (not isC) and (not isBasic) and (not isNilPy) and (not isAsm) and (not isAda) and (not isZig) and (not isLol) and (not isWs) and (not isF90) and (not isAlgol) and (not isErl) then
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
  IramCallFixCount := 0;
  SymCount := 0; ProcCount := 0;
  ProcHashReset;   { heads/tails to -1 (BSS zero is a valid proc idx) }
  SymHashReset;
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
  AsmGlobFixCount := 0;
  InlineAsmLineCount := 0; InlineAsmHoleCount := 0;
  AsmEntryOff := 0;
  AsmObjCallCount := 0;
  AsmGlobalSymCount := 0;
  AsmSoCallCount := 0;
  InLValueWrite := False;
  UClsCount := 0; UFldCount := 0; UMthCount := 0; CurSelfClass := REC_NONE;
  MethodFixCount := 0; UPropCount := 0; IMTCount := 0;
  DataPtrFixCount := 0;
  RTTIRegistryOff := -1; RTTIRegistryCount := 0;
  AnonDynArrayCount := 0;
  ResPendCount := 0; ResourceTableOff := -1; ResourceCount := 0;
  EnumTypeCount := 0; EnumValCount := 0; LastTypeEnumId := -1;
  AliasCount := 0;
  AddConst('StdErr', tyInteger, 2);
  { Predefined System ordinal limits (FPC parity — System unit consts, always
    available, no `uses`). This AddConst block is pxx's System-const surface (cf.
    StdErr). 32-bit integer family; the 64-bit High/Low(Int64) go via the
    High/Low intrinsics. Overriding these in user code is not a sane thing to do
    (FPC allows it via unit scoping; pxx does not, which is fine). }
  AddConst('MaxInt', tyInteger, 2147483647);
  AddConst('MaxLongInt', tyInteger, 2147483647);
  AddConst('MaxSmallInt', tyInteger, 32767);

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
    AddDefaultCIncludeDirs;   { pxx's crtl headers on the default <> path (unless -nostdinc) }
    CPreprocess(Source, SourceFileDir);
    if DumpCpp then begin write(Source); Halt(0); end;
    CLexAll;
    TokPos := 0;
    Next;
    ParseCProgram;
  end
  else if isAsm then
    ParseAsmProgram
  else if isRust then
  begin
    RLexAll;
    MainProgramTokCount := TokCount;
    TokPos := 0;
    Next;
    ParseRustProgram;
  end
  else if isAda then
  begin
    ALexAll;
    MainProgramTokCount := TokCount;
    TokPos := 0;
    Next;
    ParseAProgram;
  end
  else if isZig then
  begin
    ZLexAll;
    MainProgramTokCount := TokCount;
    TokPos := 0;
    Next;
    ParseZigProgram;
  end
  else if isLol then
  begin
    LLexAll;
    MainProgramTokCount := TokCount;
    TokPos := 0;
    Next;
    ParseLProgram;
  end
  else if isWs then
    { Whitespace has NO token stream — the frontend reads Source directly
      (see wparser.inc's header for why that is the probe's point). }
    ParseWsProgram
  else if isF90 then
  begin
    FLexAll;
    MainProgramTokCount := TokCount;
    TokPos := 0;
    Next;
    ParseFProgram;
  end
  else if isAlgol then
  begin
    GLexAll;
    MainProgramTokCount := TokCount;
    TokPos := 0;
    Next;
    ParseGProgram;
  end
  else if isErl then
  begin
    ELexAll;
    MainProgramTokCount := TokCount;
    TokPos := 0;
    Next;
    ParseEProgram;
  end
  else
  begin
    LexAll;
    DbgMainTokEnd := TokCount;   { -g: main-file token boundary (units appended after) }
    TokPos := 0;
    Next;
    ParseProgram;
  end;
  if (not isC) and (not isBasic) and (not isNilPy) and (not isAsm) and (not isRust) and (not isAda) and (not isZig) and (not isLol) and (not isWs) and (not isF90) and (not isAlgol) and (not isErl) then
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
    else if Fixups[i].DataOff <= -ENUM_RTTI_DATAREF_BASE then
    begin
      { TypeInfo(TEnum): resolve to the enum's RTTI blob. Tested BEFORE the others because
        the classref branch below matches every sentinel <= -CLASSREF_DATAREF_BASE. }
      j := -Fixups[i].DataOff - ENUM_RTTI_DATAREF_BASE;
      if (j >= 0) and (j < EnumTypeCount) and (EnumTypeRTTIOff[j] >= 0) then
        Fixups[i].DataOff := EnumTypeRTTIOff[j]
      else
        Error('TypeInfo of an enum type with no RTTI');
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
  if DebugTrace then
    for i := 0 to ProcCount - 1 do
      writeln('proc ', i, ': ', Procs[i].Name, ' at ', Procs[i].BodyAddr);
  { --proc-map: one "HEXVADDR name" line per emitted routine, for feeding a
    profiler (perf script | awk lookup) — pxx binaries carry no .symtab. x86-64
    static layout only (the optimization work targets the host first); the VA
    matches the non-dynamic ELF entry math (LOAD_ADDR + CODE_OFFSET + BodyAddr;
    a dynamic build shifts by the dynamic header delta). }
  if DumpProcMap and (TargetArch = TARGET_X86_64) then
    for i := 0 to ProcCount - 1 do
      if Procs[i].BodyAddr >= 0 then
        writeln(StdErr, 'PROC ', IntToHexStr(LOAD_ADDR + CODE_OFFSET + Procs[i].BodyAddr, 8), ' ', Procs[i].Name);
  if MeasureRegcall then
  begin
    writeln(StdErr, 'REGCALL-MEASURE: bodies-with-params=', RegcallProcsWithParams,
            ' total-params=', RegcallTotalParams,
            ' eligible=', RegcallEligibleParams,
            ' addr-taken-rejects=', RegcallAddrTaken);
    writeln(StdErr, 'REGCALL-MEASURE: capture@2reg=', RegcallCapped2,
            ' capture@5reg=', RegcallCapped5,
            ' eligible-param-loads+stores=', RegcallEligibleUses);
  end;
  if MeasureInline then InlineMeasureSummary;
  if EmitSharedMode then
    writeELFSharedX64(outFile)
  else if EmitObjMode then
  begin
    if TargetArch = TARGET_X86_64 then
      writeELFRelX64(outFile)
    else
      writeELF32Rel(outFile);
  end
  else if (TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) or
     (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
    writeELF32(outFile)
  else
    writeELF(outFile);

  if EmitAsmTextMode then
  begin
    WriteDisassemblyX64(outFile + '.s');
    writeln('ok: ', outFile + '.s', '  [-S disassembly]');
  end;

  writeln('ok: ',outFile,'  [code=',CodeLen,'B  data=',DataLen,
          'B  bss=',BSSSize,'B  procs=',ProcCount,']');
end.
