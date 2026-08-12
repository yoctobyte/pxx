{ SPDX-License-Identifier: MPL-2.0 }
{ FPC-seed / strict-mode forward declarations.

  FPC compiles single-pass: a call resolves only if a routine header sits ABOVE
  it in the linear (post-{$include}) text. PXX prescans every top-level header
  first, so it never needs these. This file supplies the forwards FPC (and PXX in
  --require-forward mode) requires for helpers whose bodies live in a later .inc.

  Included from compiler.pas only when PXX_NEED_FORWARDS is set (FPC defined, or
  PXX_REQUIRE_FORWARD). Signatures MUST stay byte-identical to the bodies.
  See devdocs/progress/backlog/bug-fpc-seed-helper-ordering-after-lua-c-frontend.md }

function TypeSize(tk: TTypeKind): Integer; forward;
function RegcallScalarType(tk: TTypeKind): Boolean; forward;
function GenMakeSeq(stmt, next: Integer): Integer; forward;
function CNodeDecaysToPointer(node: Integer): Boolean; forward;
function IRLowerAddress(node: Integer): Integer; forward;
function IRNodePointerBase(node: Integer): Boolean; forward;
function IRPointerStride(node: Integer): Integer; forward;
function FindCTypedef(const name: AnsiString): Integer; forward;
procedure EnableExceptionRuntime; forward;
function IsASTLValue(node: Integer): Boolean; forward;
procedure EmitOvfCheckX64(uns: Boolean); forward;
{ Helpers added after the original forwards.inc landed, again used above their
  definition (PXX prescans; FPC needs the forward). See the ticket's recurrence. }
function NestStrOff(const s: AnsiString): Integer; forward;
function MangleSuffix(n: Integer): AnsiString; forward;
function IRAppendCall(procIdx, firstArg, classIdx, tk: Integer): Integer; forward;
function IRWrapChkBounds(value: Integer; lo, hi: Int64): Integer; forward;
{ NilPy frontend helpers used above their definition in pyparser.inc. }
function PyIntLiteralText(n: Int64): AnsiString; forward;
function PyIsPylibContainerCi(ci: Integer): Boolean; forward;
{ Picks the cursor-constructor SPELLING that matches an iterable's static type
  — see its definition; parser.inc's map()/filter() arms are above it. }
function PyIterCtorName(const base: AnsiString; tk: TTypeKind;
                        node: Integer): AnsiString; forward;
{ Materialises a cursor where a real sequence is needed. Used by `in` and the
  str-method argument path, both of which sit above its definition. }
function PyDrainIfCursor(node: Integer): Integer; forward;
{ Wraps any iterable node in a cursor — enumerate()/zip() in parser.inc. }
function PyMakeIterOf(node: Integer): Integer; forward;
{ One-argument call to a plain pylib function; PyMakeIterOf sits above it. }
function PyCallProc1(const pname: AnsiString; argNode: Integer): Integer; forward;
function PyCallMeth1(ci: Integer; const mname: AnsiString;
                     selfNode, argNode: Integer): Integer; forward;
procedure PyParseDefHeader; forward;
procedure PyApplyDefSignature(procIdx: Integer); forward;
function PyPrependResultZero(procIdx, bodyNode: Integer): Integer; forward;
