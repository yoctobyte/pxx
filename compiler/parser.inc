{ SPDX-License-Identifier: MPL-2.0 }
{$ifdef FPC}
procedure LoadFile(const path: AnsiString; var dst: AnsiString); forward;
procedure LoadFileCI(const path: AnsiString; var dst: AnsiString); forward;
{$endif}
function GetFilePath(const path: AnsiString): AnsiString; forward;
function GetFileBaseName(const path: AnsiString): AnsiString; forward;
procedure NormalizePath(var p: AnsiString); forward;
procedure ExpandIncludes(var src: AnsiString; const baseDir, selfPath: AnsiString); forward;
procedure ExpandPasMacros(var src: AnsiString); forward;
{$ifndef PXX_NO_CFRONT}
procedure ParseCUnit; forward;
procedure RegisterCMacroConsts; forward;
{$endif}
procedure EmitAnsiStringRuntime; forward;
procedure EmitDiv0Stub; forward;
procedure EmitFpcFloatErrStub; forward;
procedure EmitCodeAbsToRdx(targetOff: Integer); forward;   { ir_codegen.inc is included AFTER this file, and the FPC seed build (only it) enforces that — bug-a-fpc-seed-drift-emitasmx64-forward }
procedure EmitPyBitFloatErrStub; forward;
procedure EmitSignalRuntime; forward;
procedure EmitIoLockStubs; forward;
{$ifndef PXX_NO_I386}procedure EmitIoLockStubs386; forward;{$endif}
{$ifndef PXX_NO_AARCH64}procedure EmitIoLockStubsA64; forward;{$endif}
{$ifndef PXX_NO_AARCH64}procedure EmitSignalRuntimeA64; forward;{$endif}
procedure EmitSignalRuntimeRISCV32; forward;
{$ifndef PXX_NO_ARM32}procedure EmitSignalRuntimeArm32; forward;{$endif}
{$ifndef PXX_NO_I386}procedure EmitSignalRuntime386; forward;{$endif}
{$ifndef PXX_NO_ARM32}
procedure EmitIoLockStubsArm32; forward;
{$endif}
{ The per-arch dispatcher every frontend driver must call instead of picking a
  stub itself — see its body in ir_codegen.inc for why that is not optional. }
procedure EmitIoLockStubsForTarget; forward;
procedure EmitSignalRuntimeForTarget; forward;   { its sibling: the one place the per-arch signal runtime is chosen }

{ pxx pre-scans declarations, so a routine may be CALLED above its definition; FPC
  cannot, and the cold-bootstrap seed is built by FPC. Anything defined later in this
  file but used earlier needs a forward here, or `make bootstrap` breaks while every
  pxx-built stage stays perfectly green -- a gap only the fpc-bootstrap job sees. }
function ParamIsVarRecArray(procIdx, argNo: Integer): Boolean; forward;
function ParamIsOpenArrayScalar(procIdx, argNo: Integer): Boolean; forward;
function ByRefArgStartsExpression(constVariantParam: Boolean): Boolean; forward;
function ParamIsConstVariant(pi, slot: Integer): Boolean; forward;
function ParseClassRecordSelectors(node, recId: Integer; var outTk: TTypeKind): Integer; forward;
function ParseMetaclassMemberTail(node, mcCi: Integer; var outTk: TTypeKind;
                                  var outRec: Integer; var finished: Boolean): Integer; forward;  { the ONE member-on-a-class-reference parser -- see its body }
function PyParseClassRecordSelectors(node, recId: Integer; var outTk: TTypeKind): Integer; forward;  { NilPy twin (pyparser.inc) }


{ ===== DWARF -g multi-file line table — carved out into `dbg_filetable.inc`. =
  TRACK A owns that file: which file a token came from is a debug-info
  question, not a Pascal one. Included from compiler.pas immediately after
  this one, in this position. }

{ ===== The AST arena — carved out into `ast_arena.inc`. ======================
  TRACK A owns that file: the AST is what every frontend shares. Included from
  compiler.pas immediately after this one, in this position. }

{ ===== Inline routine expansion — carved out into `inline_expand.inc`. =======
  TRACK A owns that file (and Track O tags it), not a frontend. Included from
  compiler.pas immediately after this one, in this position. }

{ ===== AST-driven symbol typing/layout — carved out into `ast_syminfer.inc`. =
  TRACK A owns that file, not a frontend. Included from compiler.pas
  immediately after this one, in this position. }

procedure ParseExpr; forward;
{ ===== The NilPy frontend's forwards — carved out into `pyforwards.inc`. =====
  Track N owns that file. Included from compiler.pas immediately after this
  one, in this position. }

{ ===== Pascal names/qualifiers/set consts — carved out into `pasparser_name.inc`.
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal class/record members — carved out into `pasparser_class.inc`. ==
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal generics — carved out into `pasparser_generic.inc`. ============
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal calls/operators/directives — carved out into `pasparser_call.inc`.
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal designators/selectors — carved out into `pasparser_lval.inc`. ==
  Included from compiler.pas immediately after this file, in this position. }

{ ===== The Pascal expression parser — carved out into `pasparser_expr.inc`. ==
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal statement parsing — carved out into `pasparser_stmt.inc`. ======
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal declaration parsing — carved out into `pasparser_decl.inc`. ====
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal routine parsing — carved out into `pasparser_proc.inc`. ========
  Included from compiler.pas immediately after this file, in this position. }

{ ===== Pascal program/unit driver — ParseProgram & co. ========================

  Carved out of this file into `pasparser_prog.inc`
  (refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files).

  It is included from `compiler.pas` on the line immediately after this file,
  NOT by a `{$include}` here, because a nested include cannot be used in the
  compiler's own source: `make compiler/pascal26` compiles it with the PINNED
  binary, and a binary that predates recursive expansion drops the directive.
  A flat list in compiler.pas is also how every other frontend is spelled. }

