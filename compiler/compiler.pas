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
  search chain as lib/rtl/lib/pcl, see compiler/pasparser_proc.inc; {$UNITPATH} is
  an FPC-only directive, silently ignored by PXX like any other directive
  it doesn't recognize). Path is relative to this source file's own
  directory (compiler/), not CWD -- portable to any checkout location. }
{$UNITPATH ../lib/asmcore}
{$ifdef FPC}
uses SysUtils, Math, BaseUnix, asmcore_base, asmcore_x64;
{$else}
uses asmcore_base, asmcore_x64;
{$endif}

{$include defs.inc}
{$include zdefs.inc}
{ The exact decimal <-> double core, ahead of every lexer that converts a float
  literal. ONE conversion for both build paths: the FPC-seeded bootstrap used
  Val and the self-host used its own rational scaler, so the two disagreed about
  what a literal MEANS — a divergence that cost nothing only because the
  compiler's own float constants are few. }
{$include exdec.inc}
function DbgFileId(const path: AnsiString): Integer; forward;   { real body in dbg_filetable.inc, included after lexer.inc and clexer.inc use it (regression-fpc-seed-drift-b1976-stale) }
procedure DbgMarkTokFile(startTok, fileId: Integer); forward;   { real body in dbg_filetable.inc, ditto }
procedure PasMarkTokFile(startTok: Integer; const path: AnsiString); forward;   { real body in dbg_filetable.inc; lexer.inc plants marks and Error reads them back }
function PasSrcOfTok(t: Integer): AnsiString; forward;                          { ditto }
procedure CMarkTokModule(startTok: Integer; const path: AnsiString); forward;    { real body in parser.inc; clexer.inc/cparser.inc call it (bug-a-fpc-seed-drift-emitasmx64-forward) }
function CPathIsCModule(const path: AnsiString): Boolean; forward;   { ditto }
procedure MarkUnitPxxDialect(unitIdx: Integer); forward;   { real body in symtab.inc; lexer.inc's {$MODE PXX} handler calls it (ditto) }
function IsNilLiteralNode(node: Integer): Boolean; forward;   { real body in ast_arena.inc; symtab.inc's overload matcher asks it about a call argument (ditto) }
{$include lexer.inc}
{$include util.inc}   { shared helpers owned by no frontend/backend — AIntToStr lived in aparser.inc until 2026-08-19. AFTER lexer.inc, not before: AppendChar is defined there. }
{$ifndef PXX_NO_CFRONT}{$include clexer.inc}{$endif}
{$ifndef PXX_NO_BASIC}{$include blexer.inc}{$endif}
{$include pylexer.inc}
{$ifndef PXX_NO_RUST}{$include rlexer.inc}{$endif}
{$ifndef PXX_NO_ADA}{$include alexer.inc}{$endif}
{$ifndef PXX_NO_ZIG}{$include zlexer.inc}{$endif}
{$ifndef PXX_NO_LOLCODE}{$include llexer.inc}{$endif}
{$ifndef PXX_NO_FORTRAN}{$include flexer.inc}{$endif}
{$ifndef PXX_NO_ALGOL}{$include glexer.inc}{$endif}
{$ifndef PXX_NO_ERLANG}{$include elexer.inc}{$endif}
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
{ symtab.inc's float writers emit through the x86-64 text assembler, which is
  defined in asmtext.inc five includes later. Only the array-of-const overload
  is called from there. Beside DbgFileId / AddDefaultCIncludeDirs, which exist
  for exactly this reason: PXX's own prescan is order-agnostic, so a missing
  forward is invisible until the FPC-seeded cold-start bootstrap
  (bug-a-fpc-seed-drift-emitasmx64-forward). }
procedure EmitAsmX64(const items: array of const); overload; forward;
{ Hoisted above symtab.inc (from beside its siblings after ir.inc) because the
  per-target EmitProcEpilog arms in symtab.inc need a dyn-array descriptor for
  the scope-exit release. Same reason as the forwards above: PXX's own prescan
  is order-agnostic, so being late is invisible until the FPC-seeded bootstrap.
  bug-a-no-dyn-array-scope-exit-release-on-four-backends }
function GetOrAllocSymRTTI(symIdx: Integer): Integer; forward;
{$include symtab.inc}
{$include abi.inc}      { the ABI oracle — after symtab.inc: it uses TypeIsFrozenString }
{$include exception_emit.inc}
{$include coroutine_emit.inc}
{$include thread_emit.inc}
{$include asmenc.inc}
{$include asmtext.inc}
{$ifndef PXX_NO_I386}{$include asmtext_386.inc}{$endif}
{$include asmtext_rv32.inc}
{$ifndef PXX_NO_AARCH64}{$include asmtext_a64.inc}{$endif}
{$ifndef PXX_NO_ARM32}{$include asmtext_arm32.inc}{$endif}
{$include asmtext_xtensa.inc}
{$ifndef PXX_NO_CFRONT}procedure CPreprocess(var src: AnsiString; const baseDir: AnsiString); forward;{$endif}
procedure AddDefaultCIncludeDirs; forward;   { the C unit pull in pasparser_proc.inc needs it too }
{ stubs for any frontend omitted from this build; no-op in the default }
{$include frontend_stubs.inc}
{ Cross-frontend forward declarations the FPC seed needs, and the map of where
  the old parser.inc went. }
{$include frontend_forwards.inc}
{ The slices of the old 37,249-line parser.inc, listed in their ORIGINAL order
  — each is a contiguous range re-included where it sat, which is what makes the
  carve-out provable by the self-host fixedpoint rather than by reading it.
  Track A owns the first four (AST and debug-info machinery that was never
  Pascal), Track N owns pyforwards.inc, Track P owns the pasparser_* set; the
  map is in frontend_forwards.inc. Flat rather than nested: this file is
  compiled by the PINNED binary, so it can only use include forms that binary
  already understands. }
{$include dbg_filetable.inc}
{$include ast_arena.inc}
{$include inline_expand.inc}
{$include ast_syminfer.inc}
{$include pyforwards.inc}
{$include pasparser_name.inc}
{$include pasparser_class.inc}
{$include pasparser_generic.inc}
{$include pasparser_call.inc}
{$include pasparser_lval.inc}
{$include pasparser_expr.inc}
{$include pasparser_stmt.inc}
{$include pasparser_decl.inc}
{$include pasparser_proc.inc}
{$include pasparser_prog.inc}
{$include ir.inc}
function GetOrAllocNodeDynDesc(node: Integer): Integer; forward;
function GetOrAllocDynUniqueDesc(node: Integer): Integer; forward;
{ "does this operand already own its +1" — the ONE predicate for managed-string
  ownership, body in ir_codegen.inc. Forwarded here because the cross backends
  are included BEFORE it and each had hand-rolled a narrower copy that listed
  IR_BINOP only, so every `'lit' + F(x)` leaked F's result on all four targets
  (bug-a-a-string-function-result-in-a-concat-leaks-on-every-cross-target). }
function IRNodeOwnsManagedStr(n: Integer): Boolean; forward;
{$ifndef PXX_NO_AARCH64}{$include ir_codegen_aarch64.inc}{$endif}
{$ifndef PXX_NO_I386}{$include ir_codegen386.inc}{$endif}
{$ifndef PXX_NO_ARM32}{$include ir_codegen_arm32.inc}{$endif}
{$include ir_codegen_riscv32.inc}
{$include ir_codegen_xtensa.inc}
{$include ir_codegen.inc}
{$include asmdisasm_x64.inc}
{ Generated crtl function -> header map (tools/gen_crtl_map.py). Must precede
  cparser.inc, whose CCrtlHeaderForName reads it. Regenerate after adding a crtl
  function; lib-test runs gen_crtl_map.py --check and fails when it is stale. }
{$include crtl_names.inc}
{$ifndef PXX_NO_CFRONT}{$include cparser.inc}{$endif}
{$ifndef PXX_NO_BASIC}{$include bparser.inc}{$endif}
{$include pyparser.inc}
{$ifndef PXX_NO_RUST}{$include rparser.inc}{$endif}
{$ifndef PXX_NO_ADA}{$include aparser.inc}{$endif}
{$ifndef PXX_NO_ZIG}{$include zparser.inc}{$endif}
{$ifndef PXX_NO_LOLCODE}{$include lparser.inc}{$endif}
{$ifndef PXX_NO_WHITESPACE}{$include wparser.inc}{$endif}
{$ifndef PXX_NO_FORTRAN}{$include fparser.inc}{$endif}
{$ifndef PXX_NO_ALGOL}{$include gparser.inc}{$endif}
{$ifndef PXX_NO_ERLANG}{$include eparser.inc}{$endif}
{$include elfwriter.inc}
{$include rtti_emit.inc}
{$include resources_emit.inc}
{$ifndef PXX_NO_CFRONT}{$include cpreproc.inc}{$endif}
{$include asmfront.inc}

{ ===== Main ===== }

var inFile, outFile, option, exePath: AnsiString; readingOptions: Boolean; n, i, j, probeFd: Integer;
begin
{$ifdef FPC}
  { The exact-decimal core in exdec.inc is lib/rtl code, written for a runtime
    where float exceptions are MASKED — which is pxx's (see
    feature-float-exception-mask-control). Its decimal->double seed estimate
    deliberately overflows to Inf and is never trusted; the exact search that
    follows proves the answer. FPC unmasks by default, so the FPC-seeded
    bootstrap died with EOverflow while compiling a float literal. Masking here
    makes both build paths behave identically, which is the property the whole
    conversion exists to have. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
                    exOverflow, exUnderflow, exPrecision]);
{$endif}
  DebugTrace := False;
  DebugInfo := False;
  FpcFloatErrors := False;
  FpcMemErrors := False;
  DbgMainTokEnd := MAX_TOKENS;
  CCharSignedOpt := -1;   { -1 = follow the target psABI; see CPlainCharSigned }
  DumpIR := False;
  DumpProcMap := False;
  EmitMapFile := True;   { default on; --no-map suppresses }
  MeasureRegcall := False;
  RegcallProcsWithParams := 0;
  RegcallTotalParams := 0;
  RegcallEligibleParams := 0;
  RegcallAddrTaken := 0;
  RegcallCapped2 := 0;
  RegcallCapped5 := 0;
  RegcallEligibleUses := 0;
  MeasureInline := False;
  InlineASTNext := 0;
  ASTArenaFloor := INLINE_AST_RESERVE;  { raised while a NilPy module parse is live — see defs.inc }
  ASTNodeCount := INLINE_AST_RESERVE;   { per-proc AST starts above the low inline reserve; the per-body resets restore this, but the FIRST allocation (before any reset) must not land in [0..INLINE_AST_RESERVE) and collide with retained inline nodes }
  EnsureTokCapacity(65536);   { bootstrap the dynamic token arrays before any lexer runs }
  InliningActive := 0;
  OptLevel := 2;   { -O2 is the default (feature-optimization-levels): ~1.34x faster / ~11% smaller, self-host -O2 fixedpoint byte-identical. -O0 is still selectable and remains the byte-identity reference; opt passes gate on OptLevel>=tier. }
  OptLevelExplicit := False;
  RcSuppressAssign := False;
  WarnedMissedFold := False;
  WarnMissedFold := False;
  DumpCpp := False;
  FrameIntrinsicUsed := False;
  NoStdInc := False;
  CUseSystemLibs := False;
  CSystemLibCount := 0;
  CrtlSrcPulledCount := 0;
  WarnSelfResult := True;   { on by default; --no-warn-self-result silences }
  WarnUsesLeak := False;
  AmbientUnitCount := 0;
  PxxDialectUnitCount := 0;
  MainPxxDialect := False;
  CTUnitCount := 0;
  CModRangeCount := 0;
  DeclVisibilityProbe := False;
  UsesInjected := False;
  VisCacheUnit := -2;
  VisCacheEdges := -1;
  WarnIgnoredDirectives := False;
  UsesEdgeCount := 0;
  DumpRTTI := False;
  TargetArch := TARGET_X86_64;
  XtensaABI := XTENSA_ABI_CALL0;
  XtensaSoftDivide := False;
  XtensaHasFpu := False;
  XtensaFastDoubles := False;
  TARGET_PTR_SIZE := 8;
  EmitObjMode := False;
  TlsMainInstalled := False;
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
    else if option = '--no-map' then
    begin
      EmitMapFile := False;
      Inc(i);
    end
    else if option = '--map' then
    begin
      EmitMapFile := True;
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
{$ifdef PXX_NO_I386}
      { A reduced build refuses the target at the OPTION, not deep in codegen:
        the omission is a property of this binary, so say so where the user
        typed it. }
      Error('--target=i386: this compiler was built without the i386 backend (-dPXX_NO_I386)');
{$endif}
      TargetArch := TARGET_I386;
      Inc(i);
    end
    else if option = '--target=aarch64' then
    begin
{$ifdef PXX_NO_AARCH64}
      Error('--target=aarch64: this compiler was built without the aarch64 backend (-dPXX_NO_AARCH64)');
{$endif}
      TargetArch := TARGET_AARCH64;
      Inc(i);
    end
    else if option = '--target=arm32' then
    begin
{$ifdef PXX_NO_ARM32}
      Error('--target=arm32: this compiler was built without the arm32 backend (-dPXX_NO_ARM32)');
{$endif}
      TargetArch := TARGET_ARM32;
      Inc(i);
    end
    else if option = '--target=xtensa' then
    begin
      TargetArch := TARGET_XTENSA;
      Inc(i);
    end
    { A SoC TARGET — `--target=esp32c6`. IDF's own spelling, so `$IDF_TARGET`
      passes straight through. It implies the ISA and selects the capability
      row; the generic `--target=riscv32` / `--target=xtensa` above keep meaning
      what they always have (esp32c3 / esp32s3 capabilities), which is why no
      existing command line changes behaviour. Carried in the target namespace
      rather than a second --esp-chip axis so an ISA/chip contradiction cannot
      be expressed at all.
      decide-esp-soc-axis-and-capability-table }
    else if (Length(option) > 9) and (Copy(option, 1, 9) = '--target=') and
            (SocFromName(Copy(option, 10, Length(option) - 9)) <> SOC_NONE) then
    begin
      TargetSoc := SocFromName(Copy(option, 10, Length(option) - 9));
      if SocIsXtensa(TargetSoc) then TargetArch := TARGET_XTENSA
      else TargetArch := TARGET_RISCV32;
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
    else if (Length(option) > 2) and (option[1] = '-') and (option[2] = 'M') then
    begin
      { FPC's `-M<mode>` (-Mdelphi, -Mobjfpc, -Mtp, ...). Real Delphi-targeting
        projects set the dialect in the BUILD rather than in each source, so
        their files carry no {$MODE} line at all — without this pxx compiled them
        in the default objfpc-ish dialect silently, and the deltas are the quiet
        kind (a bare paramless own-name read is a recursive call in delphi and a
        Result read in objfpc). compat-pascal-no-command-line-mode-switch.

        Same policy as the {$MODE} directive: only `delphi` changes behaviour,
        every other mode name maps to the default dialect and is accepted but
        inert, so a build script's -Mtp/-Miso does not fail on an unknown option.
        `delphiunicode` is delphi for our purposes.

        Safe to assign directly here: PasInitDefines (which resets DelphiMode)
        runs ONCE just above this loop, not per source, so nothing clobbers it
        afterwards — and a source-level {$MODE} still wins, because directives are
        honoured later during lexing. Both are gated. }
      DelphiMode := CaseEqual(Copy(option, 3, Length(option) - 2), 'delphi') or
                    CaseEqual(Copy(option, 3, Length(option) - 2), 'delphiunicode');
      NestedComments := not DelphiMode;
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
    else if option = '--fpc-float-errors' then
    begin
      { Emulate FPC's float error behaviour: unmask exInvalidOp / exZeroDivide /
        exOverflow at entry (FPC's own default mask, measured) and install a
        SIGFPE hook that prints the matching FPC runtime error and exits with
        it. OPT-IN — pxx's default is and stays quiet IEEE (inf/NaN propagate),
        which is the better default for measurement/streaming data with
        out-of-bounds inputs (user, 2026-07-02). See
        feature-float-exception-mask-control. }
      FpcFloatErrors := True;
      Inc(i);
    end
    else if option = '--fpc-mem-errors' then
    begin
      { Emulate FPC's MEMORY fault behaviour: hook SIGSEGV/SIGBUS so a nil read,
        a nil write, a call through a nil procvar, a method on a nil object or a
        wild array store prints `Runtime error 216 (...)` and exits 216, the way
        FPC does — instead of dying on the kernel default with no message at all
        and exit 139.

        OPT-IN, exactly like --fpc-float-errors above and for the same reason:
        installing a SIGSEGV handler changes how EVERY pxx binary dies, and
        suppresses the core dump a debugger would want. Whether it should become
        the DEFAULT is a live question for the user, parked as
        decide-segv-runtime-error-default; this flag is what makes the behaviour
        available either way.
        bug-a-a-memory-fault-is-a-raw-sigsegv-not-runtime-error-216 }
      FpcMemErrors := True;
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
    else if option = '--no-nil-check' then
    begin
      { Opt out of the emitted nil check at call-shaped sites (default on).
        The check turns a jump-to-address-0 into "Runtime error 216" — or, with
        sysutils in, a catchable EAccessViolation — at a site the compiler
        knows, instead of a fault with no usable PC.
        feature-a-emitted-nil-checks }
      NoNilCheck := True;
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
      { Kept for compatibility with scripts that passed it while it was opt-in;
        it is the default now. }
      WarnSelfResult := True;
      Inc(i);
    end
    else if option = '--no-warn-self-result' then
    begin
      { Silence the paramless bare-own-name warning. It is ON by default because
        that construct is the one place the reference dialects DISAGREE — objfpc
        reads the function's Result, delphi emits a recursive call — so the same
        line means two different things and pxx used to pick one silently. The
        idiom is legal and this is only a warning, so old sources still build;
        pass this when you have audited them and want the noise gone. }
      WarnSelfResult := False;
      Inc(i);
    end
    else if option = '--warn-uses-leak' then
    begin
      { bug-pascal-uses-is-transitive measurement step: warn whenever a name
        resolves through a unit not reachable via the real (non-transitive)
        Pascal uses rule. Opt-in and read-only — resolution itself is
        unchanged, this only counts what a real rule would break. }
      WarnUsesLeak := True;
      Inc(i);
    end
    else if (option = '--strict-uses') or (option = '--no-strict-uses') then
    begin
      { Accepted and IGNORED. The rule is unconditional as of 2026-08-15 and
        there is no switch for it, because a switch never made sense: a `uses`
        clause is in the namespace of the unit that wrote it, in every language
        that has the construct, and "should my imports leak into my importers"
        is not a dialect question (user). Kept only so an in-flight script or a
        ticket write-up that passes the old flag does not fail to compile;
        delete once those are gone. bug-pascal-uses-is-transitive. }
      Inc(i);
    end
    else if option = '--warn-ignored-directives' then
    begin
      { feature-pascal-warn-on-unfulfillable-directive: a routine directive that
        is accepted but cannot be honored is silently dropped, so the source
        keeps claiming something the build does not do. Opt-in and diagnostic
        only — nothing about codegen changes. Deliberately NOT covering the hint
        directives (deprecated/platform/...), which are meant to be inert until
        usage warnings exist and would fire on ordinary FPC source. }
      WarnIgnoredDirectives := True;
      Inc(i);
    end
    else if option = '--strict-overload' then
    begin
      StrictOverload := True;
      Inc(i);
    end
    else if option = '--strict-overload-width' then
    begin
      { FPC-parity NARROWEST-THAT-FITS choice among integer overloads. Standalone
        like --strict-overload, and for the same reason: it changes which body a
        call in the RTL and the corpora binds to, so enrolling it in the
        --strict-fpc umbrella is a separate, measured call.
        compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload }
      StrictOverloadWidth := True;
      Inc(i);
    end
    else if option = '--strict-operator' then
    begin
      { FPC-parity operator-overload rejections (= / <> on class operands).
        PXX's lax default allows value-equality operators on classes. }
      StrictOperator := True;
      Inc(i);
    end
    else if option = '--strict-case' then
    begin
      { FPC-parity case-label diagnostics (inverted ranges, duplicate/
        overlapping labels). PXX's lax default keeps first-match semantics. }
      StrictCase := True;
      Inc(i);
    end
    else if option = '--strict-python' then
    begin
      { CPython-parity umbrella for the NilPy frontend — the peer of
        --strict-fpc, and deliberately shipped BEFORE the rules that will use
        it (user, 2026-08-13): the dialect's laxities and its EXTENSIONS both
        need a declared place to be refused, and adding the flag with the first
        rule would mean the first rule also has to invent the flag. NilPy stays
        lax by default: CPython is strict for its own reasons, and where we
        have no reason of our own we do not copy the restriction.
        Wired rules live in devdocs/dev/nilpy-semantics-divergences.md; each
        lands with its own test and its own diagnostic through PyStrictRefuse. }
      StrictPython := True;
      Inc(i);
    end
    else if option = '--strict-visibility' then
    begin
      { FPC-parity member access control (private/protected/strict). PXX's lax
        default parses the markers but grants access from anywhere. }
      StrictVisibility := True;
      Inc(i);
    end
    else if option = '--strict-fpc' then
    begin
      { Umbrella: every FPC-parity behaviour flag at once (case, operator,
        visibility, overload, require-forward). Opt-in; the lax dialect is
        unchanged by default (override/overload freely stays first-class —
        platform softfloat-in-builtin, RTL, user code all override at will).
        --mimic-fpc = this + declaring FPC defined. }
      EnableStrictFpc;
      Inc(i);
    end
    else if option = '--threadsafe' then
    begin
      ThreadSafeMode := True;
      Inc(i);
    end
    else if option = '--no-shims' then
    begin
      { Refuse every mimic_<module> substitution: an import must resolve to a
        real unit of that name or fail. This is what turns "compiled without
        compatibility shims" from a claim into a checked property. }
      NoShims := True;
      Inc(i);
    end
    else if option = '--mimic-fpc-compiler' then
    begin
      { --mimic-fpc PLUS the build-config define profile FPC's makefile injects
        when compiling FPC's own COMPILER. Its sources are parameterised: every
        unit does `{$i fpcdefs.inc}`, which derives ~40 cpu* / SUPPORT_* defines
        from ONE build-time CPU define and derives nothing at all without it.
        The defines land at PasApplyMimicCompilerDefines below, once the target
        is known — the profile follows --target, so a cross probe gets the right
        one. Checked, not tested by proxy: pxx under this flag and a real
        `fpc -dx86_64` agree on all seven probed derivations.
        feature-mimic-fpc-compiler-define-profile }
      MimicFpcCompiler := True;
      MimicFpc := True;
      EnableStrictFpc;
      IChecksVal := True;
      Inc(i);
    end
    else if option = '--mimic-fpc' then
    begin
      MimicFpc := True;
      { mimic == "behave like FPC" == the --strict-fpc umbrella (case / operator /
        visibility / require-forward — all validated green across fgl, Synapse,
        fpjson 203/203 and the conformance pass-set)... }
      EnableStrictFpc;
      { ...PLUS what makes pxx claim to BE FPC, which --strict-fpc alone does not:
        FPC defaults {$I+} ON (the pxx-lax default stays quiet pending the user's
        dialect call — feature-pascal-io-checks-i-plus), and the curated FPC define
        set installed at lex time by {$MIMIC FPC}/PasApplyMimicDefines.
        NOT included (in either --strict-fpc or here): StrictOverload — our RTL
        uses undirectived overloads by design, so it would fail to compile the
        very corpora --mimic-fpc exists to build; see EnableStrictFpc. }
      IChecksVal := True;
      Inc(i);
    end
    else if (option = '--strict') or (option = '--require-forward') then
    begin
      { FPC-parity routine visibility: no pre-scan auto-forward — a routine must
        be defined above the call, be `forward;`-declared, sit in an interface
        section, or be a class method (feature-require-forward-strict-mode).
        `--strict` is the umbrella name; require-forward is its first check. }
      RequireForward := True;
      Inc(i);
    end
    else if option = '--permissive-overload' then
    begin
      StrictOverload := False;
      Inc(i);
    end
    else if option = '-fsigned-char' then
    begin
      { Override the target psABI's plain-`char` signedness; real projects pass
        these. See CPlainCharSigned (cparser.inc), the single source. }
      CCharSignedOpt := 1;
      Inc(i);
    end
    else if option = '-funsigned-char' then
    begin
      CCharSignedOpt := 0;
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
{$ifndef PXX_NO_CFRONT}
      AddCIncludeDir(PasOptionTail(option, 3));
{$endif}
      { the Pascal half of -I runs in every configuration }
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
  { Default the SoC from the ISA when a generic target was named — exactly the
    assumption those spellings have always carried, now stated once instead of
    being implied in the validation message, the two IRAM constants and the
    encoder header. decide-esp-soc-axis-and-capability-table }
  if TargetSoc = SOC_NONE then
  begin
    if TargetArch = TARGET_XTENSA then TargetSoc := SOC_ESP32S3
    else if TargetArch = TARGET_RISCV32 then TargetSoc := SOC_ESP32C3;
  end;
  if EspBareBoot and (TargetArch <> TARGET_RISCV32) and (TargetArch <> TARGET_XTENSA) then
  begin writeln(StdErr, '--esp-profile=bare requires an ESP target: a SoC name '
        + '(--target=esp32c3, esp32s3, ...) or the generic --target=riscv32 / '
        + '--target=xtensa, which mean esp32c3 / esp32s3'); Halt(1); end;
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
  { AFTER PasApplyTargetDefines and after the target is settled: the compiler
    profile picks its CPU define from TargetArch. }
  if MimicFpcCompiler then PasApplyMimicCompilerDefines
  else if MimicFpc then PasApplyMimicDefines;
  { -g (DWARF Tier-1) implies -O0 unless the user explicitly chose an -O level:
    opt passes (inline, DCE, jump threading) relocate/elide source lines and small
    functions, so breakpoints and single-step break. `-g -O2` is still honoured for
    users who accept degraded debug info. See feature-optimization-levels. }
  if DebugInfo and not OptLevelExplicit then OptLevel := 0;
  if ParamCount < i then
    begin writeln(StdErr,'usage: pascal26/PXX [--debug] [--dump-ir] [-dNAME] [-uNAME] [-Mobjfpc] [--strict-overload] [--strict-operator] [--strict-case] [--strict-python] [--mimic-fpc] [--mimic-fpc-compiler] [--fpc-mem-errors] [--no-nil-check] [--no-unhandled-handler] <src> [out]'); Halt(1); end;

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
  isNilPy := ((n >= 4) and (inFile[n] = 'y') and (inFile[n-1] = 'p') and (inFile[n-2] = 'n') and (inFile[n-3] = '.'))
             or ((n >= 3) and (inFile[n] = 'y') and (inFile[n-1] = 'p') and (inFile[n-2] = '.'));
  isAsm := (n >= 4) and (inFile[n] = 'm') and (inFile[n-1] = 's') and (inFile[n-2] = 'a') and (inFile[n-3] = '.');
  isRust := (n >= 3) and (inFile[n] = 's') and (inFile[n-1] = 'r') and (inFile[n-2] = '.');
  isAda := (n >= 4) and (inFile[n] = 'b') and (inFile[n-1] = 'd') and (inFile[n-2] = 'a') and (inFile[n-3] = '.');
  isZig := (n >= 4) and (inFile[n] = 'g') and (inFile[n-1] = 'i') and (inFile[n-2] = 'z') and (inFile[n-3] = '.');
  isLol := (n >= 4) and (inFile[n] = 'l') and (inFile[n-1] = 'o') and (inFile[n-2] = 'l') and (inFile[n-3] = '.');
  isWs := (n >= 3) and (inFile[n] = 's') and (inFile[n-1] = 'w') and (inFile[n-2] = '.');
  isF90 := (n >= 5) and (inFile[n] = '0') and (inFile[n-1] = '9') and (inFile[n-2] = 'f') and (inFile[n-3] = '.');
  isAlgol := (n >= 5) and (inFile[n] = 'g') and (inFile[n-1] = 'l') and (inFile[n-2] = 'a') and (inFile[n-3] = '.');
  isErl := (n >= 5) and (inFile[n] = 'l') and (inFile[n-1] = 'r') and (inFile[n-2] = 'e') and (inFile[n-3] = '.');

  { The MAIN input must EXIST. LoadFile answers "" for an unopenable path, which
    is indistinguishable from a genuinely empty file — and an empty NilPy source
    is a perfectly valid (empty) program, so `pxx typo.py out` reported `ok`,
    exited 0, and emitted a runnable binary that did nothing. A permission-denied
    source did the same, swallowing the EACCES entirely. Pascal only looked
    better by accident: the empty source fell through to the units path and
    failed with a bewildering complaint about `unit builtinheap`.
    Checked HERE, at the driver, rather than inside LoadFile: units and includes
    rely on empty-means-absent to drive their own search chains, and tightening
    the shared routine would break every one of them
    (bug-a-missing-source-file-compiles-to-an-empty-program). }
  probeFd := sysopen(inFile, 0);
  if probeFd < 0 then
  begin
    writeln('pascal26: error: cannot read input file: ', inFile);
    Halt(1);
  end;
  sysclose(probeFd);

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
  if (not NoDefaultRtl) and (not TargetIsEspClass) then
  begin
    { ExeDir-anchored (the installed layout: <root>/compiler/ -> ../lib/...) plus
      a CWD-relative fallback, mirroring ParseUsesUnit's own search chain. The
      latter covers the self-host tests, which run a /tmp copy of the compiler
      with CWD at the repo root, so ExeDir-relative ('/tmp/../lib/...') misses. }
    if ExeDir <> '' then
    begin
      AddPasUnitDir(ExeDir + '../lib/rtl/platform/posix/');
      { The STABLE binary lives at <root>/stable_linux_amd64/<profile>/, two
        levels down, so its '../lib' misses. Add the two-levels-up spelling as
        well rather than probe: an extra non-existent search dir costs one
        failed open, and getting this wrong made `uses SysUtils` resolve and
        then die on its own `uses platform_backend`
        (bug-a-uses-sysutils-silently-no-ops-when-the-rtl-is-not-on-the-search-path). }
      AddPasUnitDir(ExeDir + '../../lib/rtl/platform/posix/');
    end;
    AddPasUnitDir('lib/rtl/platform/posix/');
  end;
  { lib/asmcore resolution (asmcore_base/asmcore_x64, both for the compiler's
    own .asm frontend / inline-asm branches and for any user program) is now a
    first-class peer of RTL/PCL in ParseUsesUnit's own search chain — no
    AddPasUnitDir needed here, see compiler/pasparser_proc.inc (asmdir). }
  CompiledUnitCount := 0;
  UnitAliasCount := 0;
  InitProcCount := 0;
  FiniProcCount := 0;
  FiniRunnerProc := -1;
  FiniGuardSym := -1;
  InInterface := False;
  PreScanPass := False;
  DeclItemCount := 0;
  if (not isC) and (not isBasic) and (not isNilPy) and (not isAsm) and (not isAda) and (not isZig) and (not isLol) and (not isWs) and (not isF90) and (not isAlgol) and (not isErl) then
    ExpandIncludes(Source, SourceFileDir, DbgSrcName);
    ExpandPasMacros(Source);
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
  KeyCount := 0;
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
  ASTArenaFloor := INLINE_AST_RESERVE;
  ASTNodeCount := INLINE_AST_RESERVE; CurASTNode := -1;   { per-proc AST above the low inline reserve (dynamic AST arrays) }
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
  TypeInfoReqCount := 0;
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

  { The main thread's TLS block, at code offset 0 = the ELF entry point, so it is
    installed before any frontend's code runs. One call site rather than one per
    driver: each frontend emits its own entry sequence and only Pascal's puts
    anything in it, so the per-driver shape is the one that produced
    bug-a-threadsafe-segfaults-on-every-nilpy-program. Skipped for .asm, whose
    program IS the emitted bytes and whose entry point is overridable
    (AsmEntryOff). x86-64 only, inside the emitter. }
  if not isAsm then EmitTlsMainInstall;

  if isNilPy then
  begin
    PyLoopElseFlag := -1;   { no enclosing loop yet; 0 is a real Syms index }
    for i := 0 to MAX_UCLASS - 1 do
    begin
      PyDcEqProc[i] := -1;
      PyDcReprProc[i] := -1;
    end;
    PyExpandFStrings;
    PyLexAll(False);
    { -g: main-file token boundary, exactly as the Pascal branch below sets it.
      Without it DbgMainTokEnd stayed MAX_TOKENS, so every appended unit token
      counted as main-file and stamped ITS line number onto the nodes — a
      19-line .py reported `dbg1.py:5754` (a pylib line) for every frame, which
      made the line table useless and stepping meaningless. }
    DbgMainTokEnd := TokCount;
    MainProgramTokCount := TokCount;
    TokPos := 0;
    Next;
    ParsePyProgram;
  end
  else if isBasic then
  begin
{$ifdef PXX_NO_BASIC}
    writeln(StdErr, 'this compiler was built without the BASIC frontend (built with PXX_NO_BASIC); rebuild without that define to compile BASIC sources');
    Halt(1);
{$else}
    BLexAll(True);
    MainProgramTokCount := TokCount;
    DbgMainTokEnd := TokCount;   { -g: see the NilPy branch above }
    TokPos := 0;
    Next;
    ParseBProgram;
{$endif}
  end
  else if isC then
  begin
{$ifdef PXX_NO_CFRONT}
    writeln(StdErr, 'this compiler was built without the C frontend (built with PXX_NO_CFRONT); rebuild without that define to compile C sources');
    Halt(1);
{$else}
    AddDefaultCIncludeDirs;   { pxx's crtl headers on the default <> path (unless -nostdinc) }
    CPreprocess(Source, SourceFileDir);
    if DumpCpp then begin write(Source); Halt(0); end;
    CLexAll;
    DbgMainTokEnd := TokCount;   { -g: see the NilPy branch above }
    TokPos := 0;
    Next;
    ParseCProgram;
{$endif}
  end
  else if isAsm then
    ParseAsmProgram
  else if isRust then
  begin
{$ifdef PXX_NO_RUST}
    writeln(StdErr, 'this compiler was built without the Rust frontend (built with PXX_NO_RUST); rebuild without that define to compile Rust sources');
    Halt(1);
{$else}
    RLexAll;
    MainProgramTokCount := TokCount;
    DbgMainTokEnd := TokCount;   { -g: see the NilPy branch above }
    TokPos := 0;
    Next;
    ParseRustProgram;
{$endif}
  end
  else if isAda then
  begin
{$ifdef PXX_NO_ADA}
    writeln(StdErr, 'this compiler was built without the Ada frontend (built with PXX_NO_ADA); rebuild without that define to compile Ada sources');
    Halt(1);
{$else}
    ALexAll;
    MainProgramTokCount := TokCount;
    DbgMainTokEnd := TokCount;   { -g: see the NilPy branch above }
    TokPos := 0;
    Next;
    ParseAProgram;
{$endif}
  end
  else if isZig then
  begin
{$ifdef PXX_NO_ZIG}
    writeln(StdErr, 'this compiler was built without the Zig frontend (built with PXX_NO_ZIG); rebuild without that define to compile Zig sources');
    Halt(1);
{$else}
    ZLexAll;
    MainProgramTokCount := TokCount;
    DbgMainTokEnd := TokCount;   { -g: see the NilPy branch above }
    TokPos := 0;
    Next;
    ParseZigProgram;
{$endif}
  end
  else if isLol then
  begin
{$ifdef PXX_NO_LOLCODE}
    writeln(StdErr, 'this compiler was built without the LOLCODE frontend (built with PXX_NO_LOLCODE); rebuild without that define to compile LOLCODE sources');
    Halt(1);
{$else}
    LLexAll;
    MainProgramTokCount := TokCount;
    DbgMainTokEnd := TokCount;   { -g: see the NilPy branch above }
    TokPos := 0;
    Next;
    ParseLProgram;
{$endif}
  end
  else if isWs then
  begin
{$ifdef PXX_NO_WHITESPACE}
    writeln(StdErr, 'this compiler was built without the Whitespace frontend (built with PXX_NO_WHITESPACE); rebuild without that define to compile Whitespace sources');
    Halt(1);
{$else}
    { Whitespace has NO token stream — the frontend reads Source directly
      (see wparser.inc's header for why that is the probe's point). }
    ParseWsProgram;
{$endif}
  end
  else if isF90 then
  begin
{$ifdef PXX_NO_FORTRAN}
    writeln(StdErr, 'this compiler was built without the Fortran frontend (built with PXX_NO_FORTRAN); rebuild without that define to compile Fortran sources');
    Halt(1);
{$else}
    FLexAll;
    MainProgramTokCount := TokCount;
    DbgMainTokEnd := TokCount;   { -g: see the NilPy branch above }
    TokPos := 0;
    Next;
    ParseFProgram;
{$endif}
  end
  else if isAlgol then
  begin
{$ifdef PXX_NO_ALGOL}
    writeln(StdErr, 'this compiler was built without the ALGOL frontend (built with PXX_NO_ALGOL); rebuild without that define to compile ALGOL sources');
    Halt(1);
{$else}
    GLexAll;
    MainProgramTokCount := TokCount;
    DbgMainTokEnd := TokCount;   { -g: see the NilPy branch above }
    TokPos := 0;
    Next;
    ParseGProgram;
{$endif}
  end
  else if isErl then
  begin
{$ifdef PXX_NO_ERLANG}
    writeln(StdErr, 'this compiler was built without the Erlang frontend (built with PXX_NO_ERLANG); rebuild without that define to compile Erlang sources');
    Halt(1);
{$else}
    ELexAll;
    MainProgramTokCount := TokCount;
    DbgMainTokEnd := TokCount;   { -g: see the NilPy branch above }
    TokPos := 0;
    Next;
    ParseEProgram;
{$endif}
  end
  else
  begin
    LexAll;
    DbgMainTokEnd := TokCount;   { -g: main-file token boundary (units appended after) }
    { -g: CLOSE the include-marker ranges. The last `{$I}` in the main file
      leaves its .inc as the open range, and DbgFileOfTok answers with the last
      range at or before a token — so without this, every token of every unit
      appended afterwards (the whole RTL) would report as that .inc, with its
      own line numbers, and land in the line table. Marking file 1 here restores
      the deliberate line-0 treatment for unmarked appended sources. }
    DbgMarkTokFile(TokCount, 1);
    TokPos := 0;
    Next;
    ParseProgram;
  end;
  { NilPy included: isinstance() resolves class identity through the same
    RTTI backlink chain (__pxxInheritsFrom) the Pascal `is` operator uses. }
  if (not isC) and (not isBasic) and (not isAsm) and (not isRust) and (not isAda) and (not isZig) and (not isLol) and (not isWs) and (not isF90) and (not isAlgol) and (not isErl) then
  begin
    EmitRTTI;
    { After EmitRTTI so it shares the same static-data region and the same
      MethodFixups pass that patches code addresses into data. }
    EmitPySignatures;
    EmitTypeInfoHeaders;
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
    else if Fixups[i].DataOff <= -PYSIGD_DATAREF_BASE then
    begin
      { A NilPy def's DEFAULTS ARRAY. Before the PYSIG branch below: more
        negative base, and that branch matches everything this one does. }
      j := -Fixups[i].DataOff - PYSIGD_DATAREF_BASE;
      if (j >= 0) and (j < PyDfltPendCount) and (PyDfltPendOff[j] >= 0) then
        Fixups[i].DataOff := PyDfltPendOff[j]
      else
        { orphaned by a rolled-back trial parse: write it to the bit bucket. The
          array slot stays PYSIG_DFLT_UNSET and the consumer complains, where the
          param name is known. See PyDfltScratchOff in defs.inc. }
        Fixups[i].DataOff := PyDfltScratchOff;
    end
    else if Fixups[i].DataOff <= -PYSIG_DATAREF_BASE then
    begin
      { A NilPy def's signature record (EmitPySignatures). Tested FIRST because
        it is the MOST negative base -- the TypeInfo branch below matches every
        sentinel at least as negative as its own, so it would swallow this one.
        See the ordering notes on the branches that follow. }
      j := -Fixups[i].DataOff - PYSIG_DATAREF_BASE;
      if (j >= 0) and (j < ProcCount) and (ProcSigOff[j] >= 0) then
        Fixups[i].DataOff := ProcSigOff[j]
      else
        { A callee that got no record -- a synthesized wrapper, or a def
          EmitPySignatures does not recognise. Point it at the ZEROED scratch
          record: TotN = 0, so the bridge fills nothing and behaves exactly as
          it did before signatures existed. This was a hard Error and it FAILED
          FOUR TESTS at once the moment a bound method crossed a module
          boundary -- a missing signature must degrade to the old behaviour,
          never refuse to build. }
        Fixups[i].DataOff := PyDfltScratchOff;
    end
    else if Fixups[i].DataOff <= -TYPEINFO_REQ_DATAREF_BASE then
    begin
      { Widened TypeInfo(T) (scalar/string/class/record): resolve to the request's
        PTypeInfo header (EmitTypeInfoHeaders). Tested BEFORE every other sentinel
        base -- it is the most negative, and the ENUM branch below would otherwise
        swallow it (every sentinel <= -ENUM_RTTI_DATAREF_BASE also satisfies
        <= -TYPEINFO_REQ_DATAREF_BASE's neighbours, so order matters here exactly
        as it does for ENUM vs CLASSREF). }
      j := -Fixups[i].DataOff - TYPEINFO_REQ_DATAREF_BASE;
      if (j >= 0) and (j < TypeInfoReqCount) and (TypeInfoReqOff[j] >= 0) then
        Fixups[i].DataOff := TypeInfoReqOff[j]
      else
        Error('TypeInfo() of a type with no RTTI header')
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
