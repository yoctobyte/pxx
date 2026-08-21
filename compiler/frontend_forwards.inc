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
procedure EmitProgramEntryForTarget(withHeapArena: Boolean; var jmpPatch: Integer); forward;
procedure PatchProgramEntryJump(jmpPatch: Integer); forward;
procedure EmitParamSpillsForTarget(procIdx, nparams: Integer); forward;
procedure EmitZeroLocalSlotForTarget(symIdx, nbytes: Integer); forward;
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
procedure ParseExpr; forward;   { body in pasparser_expr.inc — called from pasparser_call.inc,
                                  which compiler.pas includes first. pxx pre-scans and does not
                                  need this; FPC does, so dropping it breaks ONLY the seed build
                                  (bug-a-fpc-seed-drift-emitasmx64-forward). }

{ ===== Where the Pascal parser went =========================================

  This file was `parser.inc`: 37,249 lines, the second-busiest file in the
  compiler and the ONE file Tracks A and P had to serialize on. It is now the
  forward-declaration header above and nothing else, and it was renamed because
  the old name was the actual defect — `parser.inc` reads as "the parser",
  which is how a Pascal-only file came to hold the C frontend's forwards, the
  NilPy frontend's ~200 forwards, the AST arena and the DWARF file table. The
  user's framing (2026-08-18): *"parser.inc was intended as pasparser.inc ...
  what is shared is AST and IR, not the parser."*

  Every slice below is a CONTIGUOUS range of the original, re-included from
  compiler.pas in the exact position it occupied. That is deliberate and it is
  what let the self-host fixedpoint prove each move: emitted code size did not
  change by a byte across any of the fourteen cuts.

  Track P — the Pascal frontend, in compiler.pas include order:

    pasparser_name.inc      names, unit qualifiers, set constants
    pasparser_class.inc     class/record member declaration support
    pasparser_generic.inc   generics: templates and specialization
    pasparser_call.inc      operators, arguments, overloads, directives
    pasparser_lval.inc      designators and the selector chain
    pasparser_expr.inc      the precedence chain and constant expressions
    pasparser_stmt.inc      statements, for-in, generators, parallel for
    pasparser_decl.inc      type/const/var declarations, nested routines
    pasparser_proc.inc      the procedure/function parser
    pasparser_prog.inc      ParseProgram and the unit drivers

  Track N — the Nil-Python frontend:

    pyforwards.inc          the Py* forwards, and ParseArgExpr, the hook that
                            sends a call argument down the PYTHON precedence
                            chain rather than Pascal's

  Track A — language-agnostic core that had no business in a frontend's file:

    dbg_filetable.inc       DWARF -g: which file a token came from
    ast_arena.inc           the AST arena: capacity, allocation, cloning
    inline_expand.inc       inline routine expansion (also Track O)
    ast_syminfer.inc        symbol typing, stack layout, DWARF var snapshot

  The rule these files exist to enforce, in one line: share the AST and the IR,
  DUPLICATE the parser and the lexer per language. Two similar-looking routines
  in pasparser_*.inc and pyparser.inc are the intended end state, not debt —
  a shared parser helper couples two specs and is then wrong in both.
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md

  They are listed flat in compiler.pas rather than `{$include}`d from here
  because compiler.pas is compiled by the PINNED binary, and recursive include
  expansion only landed in the compiler today
  (bug-a-a-nested-include-is-silently-dropped). Flat is also how every other
  frontend is spelled there. }
