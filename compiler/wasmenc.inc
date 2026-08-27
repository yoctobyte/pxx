{ SPDX-License-Identifier: MPL-2.0 }
{ wasmenc.inc — WebAssembly module model + binary (.wasm) writer.

  Peer of x64enc.inc / rv32enc.inc: this is where wasm BYTES are produced. We
  emit the binary ourselves and never shell out to wat2wasm — the
  self-contained-toolchain property is paid for everywhere else in this project
  and is not being spent here (devdocs/dev/wasm/CHARTER.md).

  The module MODEL declared here is shared with asmtext_wasm.inc, which renders
  the same arrays as WAT text. That sharing is deliberate: the binary and the
  text describe one structure by construction, so `wasm2wat` round-tripping to
  the same module is a property of the design rather than a coincidence two
  emitters have to keep agreeing on.

  Size fields. EVERY size — each section, and each function body inside the code
  section — is written as a 5-byte PADDED LEB128 placeholder and patched in
  place once the length is known. Non-minimal LEB128 within the u32 width limit
  is legal, and that was verified accepted by wasm-validate 1.0.36 and V8 before
  this file was written rather than assumed.

  The alternative is canonical sizes, which needs either a scratch buffer per
  nesting level or a memmove to close the gap after the fact — and doing that
  per function body would make emitting the code section quadratic. Padding buys
  a single output buffer and no shifting, for exactly 4 bytes per size field.
  Measured on the Phase 1 self-test: 219 bytes against wat2wasm's canonical 183,
  a difference of 36 = 4 x (7 sections + 2 function bodies). On a tiny module
  that reads as 20%; it is a FIXED cost per section and per function, so on
  anything real it is noise. Revisit only with a measurement on a big module,
  not on the look of that 20%.

  Index spaces. Imported functions occupy the LOW function indices; a defined
  function's index is WasmImpFuncCount + its slot here. Everything that names a
  function by index (exports, calls, the element section) goes through
  WasmFuncIndex so that offset is applied in exactly one place. }

const
  { value types (the negative-s7 encodings, written as their byte values) }
  WT_I32     = $7F;
  WT_I64     = $7E;
  WT_F32     = $7D;
  WT_F64     = $7C;
  WT_FUNCREF = $70;
  WT_VOID    = $40;   { the empty block type }

  { external kinds, for imports and exports }
  WEK_FUNC   = 0;
  WEK_TABLE  = 1;
  WEK_MEM    = 2;
  WEK_GLOBAL = 3;

  { section ids }
  WSEC_CUSTOM = 0;  WSEC_TYPE   = 1;  WSEC_IMPORT = 2;  WSEC_FUNC   = 3;
  WSEC_TABLE  = 4;  WSEC_MEM    = 5;  WSEC_GLOBAL = 6;  WSEC_EXPORT = 7;
  WSEC_START  = 8;  WSEC_ELEM   = 9;  WSEC_CODE   = 10; WSEC_DATA   = 11;

  { a handful of opcodes the writer itself needs (init exprs, bodies) }
  WOP_END       = $0B;
  WOP_I32_CONST = $41;
  WOP_I64_CONST = $42;
  WOP_F32_CONST = $43;
  WOP_F64_CONST = $44;

  { Sizing. These are fixed arrays in BSS, and they are carried by EVERY pxx
    invocation on every target, so they are not free just because no other
    target touches them. The first draft cost 66MB against the compiler's own
    76MB; this is ~20MB. BSS is zero-fill-on-demand, so pages no target touches
    never become resident and the real cost to a non-wasm build is address
    space rather than memory — but the reported figure is real and doubling it
    for a feature nobody else uses was not defensible.
    Phase 7 (the compiler itself under wasm) is the case that will actually
    strain these; re-measure there rather than guessing upward now. }
  MAX_WASM_BYTES     = 8 * 1024 * 1024;   { module output }
  MAX_WASM_BODY      = 1024 * 1024;       { one function body, scratch }
  MAX_WASM_TYPES     = 4096;
  MAX_WASM_TYPESIG   = 65536;   { flattened param/result pool }
  MAX_WASM_FUNCS     = 16384;
  MAX_WASM_LOCALS    = 131072;  { flattened local-type pool }
  MAX_WASM_VARNAMES  = 65536;   { flattened param+local NAME pool }
  MAX_WASM_CODE      = 8 * 1024 * 1024;   { flattened body-instruction pool }
  MAX_WASM_IMPORTS   = 1024;
  MAX_WASM_EXPORTS   = 4096;
  MAX_WASM_GLOBALS   = 1024;

var
  { ---- output buffer ---- }
  WB      : array[0..MAX_WASM_BYTES-1] of Byte;
  WBLen   : Integer;
  WFB     : array[0..MAX_WASM_BODY-1] of Byte;   { function-body scratch }
  WFBLen  : Integer;
  { Text companion to WFB. Every instruction emitter below appends to BOTH, at
    one call site — the generalization of x64enc.inc's EncToAsmBuffer switch.
    That is what makes the .wat and the .wasm descriptions of one body rather
    than two emitters that have to be kept agreeing. asmtext_wasm.inc renders
    the module structure around these strings and never decodes an opcode. }
  WFText  : AnsiString;
  WFIndent: Integer;

  { ---- type section: function signatures ---- }
  WasmTypeCount  : Integer;
  WasmTypeParOfs : array[0..MAX_WASM_TYPES-1] of Integer;
  WasmTypeNPar   : array[0..MAX_WASM_TYPES-1] of Integer;
  WasmTypeResOfs : array[0..MAX_WASM_TYPES-1] of Integer;
  WasmTypeNRes   : array[0..MAX_WASM_TYPES-1] of Integer;
  WasmSigPool    : array[0..MAX_WASM_TYPESIG-1] of Byte;
  WasmSigLen     : Integer;

  { ---- imports (functions only in v1; the low function index space) ---- }
  WasmImpCount   : Integer;
  WasmImpModule  : array[0..MAX_WASM_IMPORTS-1] of AnsiString;
  WasmImpName    : array[0..MAX_WASM_IMPORTS-1] of AnsiString;
  WasmImpKind    : array[0..MAX_WASM_IMPORTS-1] of Integer;
  WasmImpType    : array[0..MAX_WASM_IMPORTS-1] of Integer;  { type idx for WEK_FUNC }
  WasmImpFuncCount : Integer;   { how many of the above are WEK_FUNC }

  { ---- defined functions ---- }
  WasmFuncCount  : Integer;
  WasmFuncType   : array[0..MAX_WASM_FUNCS-1] of Integer;
  WasmFuncName   : array[0..MAX_WASM_FUNCS-1] of AnsiString;
  WasmFuncLocOfs : array[0..MAX_WASM_FUNCS-1] of Integer;
  WasmFuncNLoc   : array[0..MAX_WASM_FUNCS-1] of Integer;
  WasmLocalPool  : array[0..MAX_WASM_LOCALS-1] of Byte;
  WasmLocalLen   : Integer;
  { Names for a function's locals INDEX SPACE — params first, then declared
    locals, exactly as wasm numbers them. The instruction emitters look names up
    here rather than taking one as an argument, so a `local.get $fp` in the text
    cannot name something the (local ...) declaration did not. }
  WasmFuncVarOfs : array[0..MAX_WASM_FUNCS-1] of Integer;
  WasmFuncNVar   : array[0..MAX_WASM_FUNCS-1] of Integer;
  WasmVarNames   : array[0..MAX_WASM_VARNAMES-1] of AnsiString;
  WasmVarNameLen : Integer;
  WasmFuncCodeOfs: array[0..MAX_WASM_FUNCS-1] of Integer;
  WasmFuncCodeLen: array[0..MAX_WASM_FUNCS-1] of Integer;
  WasmFuncText   : array[0..MAX_WASM_FUNCS-1] of AnsiString;
  WasmCodePool   : array[0..MAX_WASM_CODE-1] of Byte;
  WasmCodeLen    : Integer;

  { ---- memory ---- }
  WasmMemPresent : Boolean;
  WasmMemMin     : Integer;
  WasmMemMax     : Integer;   { -1 = unbounded }

  { ---- globals ---- }
  WasmGlobCount  : Integer;
  WasmGlobType   : array[0..MAX_WASM_GLOBALS-1] of Byte;
  WasmGlobMut    : array[0..MAX_WASM_GLOBALS-1] of Boolean;
  WasmGlobInit   : array[0..MAX_WASM_GLOBALS-1] of Int64;
  WasmGlobName   : array[0..MAX_WASM_GLOBALS-1] of AnsiString;

  { ---- exports ---- }
  WasmExpCount   : Integer;
  WasmExpName    : array[0..MAX_WASM_EXPORTS-1] of AnsiString;
  WasmExpKind    : array[0..MAX_WASM_EXPORTS-1] of Integer;
  WasmExpIdx     : array[0..MAX_WASM_EXPORTS-1] of Integer;

procedure WasmFail(const msg: AnsiString);
begin
{$ifdef WASMENC_STANDALONE}
  Writeln('wasmenc: ', msg);
  Halt(1);
{$else}
  Error(msg);
{$endif}
end;

{ ===== the module model — reset and build ===== }

procedure WasmReset;
begin
  WBLen := 0; WFBLen := 0;
  WasmTypeCount := 0; WasmSigLen := 0;
  WasmImpCount := 0; WasmImpFuncCount := 0;
  WasmFuncCount := 0; WasmLocalLen := 0; WasmCodeLen := 0;
  WasmVarNameLen := 0;
  WasmMemPresent := False; WasmMemMin := 0; WasmMemMax := -1;
  WasmGlobCount := 0;
  WasmExpCount := 0;
end;

{ Intern a signature. Returns its type index, reusing an identical one — the
  type section is a set, and emitting duplicates is legal but wasteful.

  The counted form exists because a caller building a signature from
  Procs[].Params has a FIXED array and a separate count: an open array carries
  its own Length, so passing `ptypes` would intern a 32-parameter signature for
  a two-parameter function. }
function WasmAddTypeN(const params: array of Byte; np: Integer;
                      const results: array of Byte; nr: Integer): Integer;
var i, j: Integer; same: Boolean;
begin
  for i := 0 to WasmTypeCount - 1 do
    if (WasmTypeNPar[i] = np) and (WasmTypeNRes[i] = nr) then
    begin
      same := True;
      for j := 0 to np - 1 do
        if WasmSigPool[WasmTypeParOfs[i] + j] <> params[j] then same := False;
      for j := 0 to nr - 1 do
        if WasmSigPool[WasmTypeResOfs[i] + j] <> results[j] then same := False;
      if same then begin WasmAddTypeN := i; Exit; end;
    end;
  if WasmTypeCount >= MAX_WASM_TYPES then WasmFail('wasm: too many function types');
  if WasmSigLen + np + nr > MAX_WASM_TYPESIG then WasmFail('wasm: signature pool full');
  WasmTypeParOfs[WasmTypeCount] := WasmSigLen;
  WasmTypeNPar[WasmTypeCount] := np;
  for j := 0 to np - 1 do begin WasmSigPool[WasmSigLen] := params[j]; Inc(WasmSigLen); end;
  WasmTypeResOfs[WasmTypeCount] := WasmSigLen;
  WasmTypeNRes[WasmTypeCount] := nr;
  for j := 0 to nr - 1 do begin WasmSigPool[WasmSigLen] := results[j]; Inc(WasmSigLen); end;
  WasmAddTypeN := WasmTypeCount;
  Inc(WasmTypeCount);
end;

function WasmAddType(const params: array of Byte; const results: array of Byte): Integer;
begin
  WasmAddType := WasmAddTypeN(params, Length(params), results, Length(results));
end;

function WasmAddImportFunc(const modName, fldName: AnsiString; typeIdx: Integer): Integer;
begin
  if WasmImpCount >= MAX_WASM_IMPORTS then WasmFail('wasm: too many imports');
  { v1 keeps all function imports contiguous and first, so the low function
    index space is exactly [0, WasmImpFuncCount). A non-function import
    appearing before one would break that; there are none yet. }
  WasmImpModule[WasmImpCount] := modName;
  WasmImpName[WasmImpCount] := fldName;
  WasmImpKind[WasmImpCount] := WEK_FUNC;
  WasmImpType[WasmImpCount] := typeIdx;
  Inc(WasmImpCount);
  WasmAddImportFunc := WasmImpFuncCount;
  Inc(WasmImpFuncCount);
end;

{ Declare a defined function. Returns its SLOT (not its wasm function index —
  use WasmFuncIndex for that). }
function WasmAddFunc(const name: AnsiString; typeIdx: Integer): Integer;
begin
  if WasmFuncCount >= MAX_WASM_FUNCS then WasmFail('wasm: too many functions');
  WasmFuncType[WasmFuncCount] := typeIdx;
  WasmFuncName[WasmFuncCount] := name;
  WasmFuncLocOfs[WasmFuncCount] := WasmLocalLen;
  WasmFuncNLoc[WasmFuncCount] := 0;
  WasmFuncVarOfs[WasmFuncCount] := WasmVarNameLen;
  WasmFuncNVar[WasmFuncCount] := 0;
  WasmFuncCodeOfs[WasmFuncCount] := 0;
  WasmFuncCodeLen[WasmFuncCount] := 0;
  WasmAddFunc := WasmFuncCount;
  Inc(WasmFuncCount);
end;

{ The wasm function INDEX of a defined function slot — imports come first. }
function WasmFuncIndex(slot: Integer): Integer;
begin
  WasmFuncIndex := WasmImpFuncCount + slot;
end;

{ Name a PARAMETER of the most recently added function. Call once per param, in
  order, before any WasmAddLocal — params occupy the low local indices. }
procedure WasmAddParamName(slot: Integer; const nm: AnsiString);
begin
  if slot <> WasmFuncCount - 1 then
    WasmFail('wasm: params must be named on the function most recently declared');
  if WasmVarNameLen >= MAX_WASM_VARNAMES then WasmFail('wasm: var-name pool full');
  WasmVarNames[WasmVarNameLen] := nm;
  Inc(WasmVarNameLen);
  Inc(WasmFuncNVar[slot]);
end;

{ Append one local to the most recently added function, with its name. Locals
  are stored one per entry here and run-length compressed at emit time.
  Returns the local INDEX (params first), which is what local.get/set take. }
function WasmAddLocal(slot: Integer; vt: Byte; const nm: AnsiString): Integer;
begin
  if slot <> WasmFuncCount - 1 then
    WasmFail('wasm: locals must be added to the function most recently declared');
  if WasmLocalLen >= MAX_WASM_LOCALS then WasmFail('wasm: local pool full');
  if WasmVarNameLen >= MAX_WASM_VARNAMES then WasmFail('wasm: var-name pool full');
  WasmLocalPool[WasmLocalLen] := vt;
  Inc(WasmLocalLen);
  Inc(WasmFuncNLoc[slot]);
  WasmVarNames[WasmVarNameLen] := nm;
  Inc(WasmVarNameLen);
  WasmAddLocal := WasmFuncNVar[slot];
  Inc(WasmFuncNVar[slot]);
end;

{ The name of local index `idx` in the function currently being emitted. }
function WasmVarNameOf(idx: Integer): AnsiString;
var slot: Integer;
begin
  slot := WasmFuncCount - 1;
  if (slot < 0) or (idx < 0) or (idx >= WasmFuncNVar[slot]) then
    WasmVarNameOf := ''
  else
    WasmVarNameOf := WasmVarNames[WasmFuncVarOfs[slot] + idx];
end;

procedure WasmSetMemory(minPages, maxPages: Integer);
begin
  WasmMemPresent := True;
  WasmMemMin := minPages;
  WasmMemMax := maxPages;
end;

function WasmAddGlobal(const name: AnsiString; vt: Byte; mutable: Boolean; initVal: Int64): Integer;
begin
  if WasmGlobCount >= MAX_WASM_GLOBALS then WasmFail('wasm: too many globals');
  WasmGlobType[WasmGlobCount] := vt;
  WasmGlobMut[WasmGlobCount] := mutable;
  WasmGlobInit[WasmGlobCount] := initVal;
  WasmGlobName[WasmGlobCount] := name;
  WasmAddGlobal := WasmGlobCount;
  Inc(WasmGlobCount);
end;

procedure WasmAddExport(const name: AnsiString; kind, idx: Integer);
begin
  if WasmExpCount >= MAX_WASM_EXPORTS then WasmFail('wasm: too many exports');
  WasmExpName[WasmExpCount] := name;
  WasmExpKind[WasmExpCount] := kind;
  WasmExpIdx[WasmExpCount] := idx;
  Inc(WasmExpCount);
end;

{ ===== function body construction (into the scratch buffer) ===== }

procedure WasmBodyBegin;
begin
  WFBLen := 0;
  WFText := '';
  WFIndent := 4;
end;

procedure WasmBodyB(b: Byte);
begin
  if WFBLen >= MAX_WASM_BODY then WasmFail('wasm: function body too large');
  WFB[WFBLen] := b;
  Inc(WFBLen);
end;

procedure WasmBodyU32(v: Int64);
var x: Int64; b: Byte;
begin
  x := v;
  repeat
    b := Byte(x and $7F);
    x := x shr 7;
    if x <> 0 then b := b or $80;
    WasmBodyB(b);
  until x = 0;
end;

procedure WasmBodyS32(v: Int64);
var x: Int64; b: Byte; more: Boolean;
begin
  x := v;
  more := True;
  while more do
  begin
    b := Byte(x and $7F);
    x := x shr 7;                 { arithmetic shift: Pascal shr on Int64 is }
    if v < 0 then                 { logical, so sign-extend by hand }
      x := x or (Int64(-1) shl 57);
    if ((x = 0) and ((b and $40) = 0)) or ((x = -1) and ((b and $40) <> 0)) then
      more := False
    else
      b := b or $80;
    WasmBodyB(b);
  end;
end;

{ ===== instruction layer: one call site, binary + text ===== }

function WasmIndentStr: AnsiString;
var i: Integer; r: AnsiString;
begin
  r := '';
  for i := 1 to WFIndent do r := r + ' ';
  WasmIndentStr := r;
end;

procedure WasmText(const t: AnsiString);
begin
  WFText := WFText + WasmIndentStr + t + LineEnding;
end;

function WasmIntStr(v: Int64): AnsiString;
var s: AnsiString;
begin
  Str(v, s);
  WasmIntStr := s;
end;

procedure WasmI32Const(v: Int64);
begin
  WasmBodyB(WOP_I32_CONST); WasmBodyS32(v);
  WasmText('i32.const ' + WasmIntStr(v));
end;

procedure WasmI64Const(v: Int64);
begin
  WasmBodyB(WOP_I64_CONST); WasmBodyS32(v);
  WasmText('i64.const ' + WasmIntStr(v));
end;

procedure WasmLocalGet(idx: Integer);
var nm: AnsiString;
begin
  WasmBodyB($20); WasmBodyU32(idx);
  nm := WasmVarNameOf(idx);
  if nm <> '' then WasmText('local.get $' + nm)
  else WasmText('local.get ' + WasmIntStr(idx));
end;

procedure WasmLocalSet(idx: Integer);
var nm: AnsiString;
begin
  WasmBodyB($21); WasmBodyU32(idx);
  nm := WasmVarNameOf(idx);
  if nm <> '' then WasmText('local.set $' + nm)
  else WasmText('local.set ' + WasmIntStr(idx));
end;

procedure WasmGlobalGet(idx: Integer);
begin
  WasmBodyB($23); WasmBodyU32(idx);
  WasmText('global.get $' + WasmGlobName[idx]);
end;

procedure WasmGlobalSet(idx: Integer);
begin
  WasmBodyB($24); WasmBodyU32(idx);
  WasmText('global.set $' + WasmGlobName[idx]);
end;

{ align is the LOG2 alignment hint; a wrong hint is a performance note, not a
  fault — unaligned access is legal and defined (phase2-shadow-stack.md). }
procedure WasmI32Load(align, offset: Integer);
begin
  WasmBodyB($28); WasmBodyU32(align); WasmBodyU32(offset);
  WasmText('i32.load offset=' + WasmIntStr(offset)
           + ' align=' + WasmIntStr(1 shl align));
end;

procedure WasmI32Store(align, offset: Integer);
begin
  WasmBodyB($36); WasmBodyU32(align); WasmBodyU32(offset);
  WasmText('i32.store offset=' + WasmIntStr(offset)
           + ' align=' + WasmIntStr(1 shl align));
end;

procedure WasmBinop(opcode: Byte; const nm: AnsiString);
begin
  WasmBodyB(opcode);
  WasmText(nm);
end;

procedure WasmCall(funcIndex: Integer; const nm: AnsiString);
begin
  WasmBodyB($10); WasmBodyU32(funcIndex);
  if nm <> '' then WasmText('call $' + nm)
  else WasmText('call ' + WasmIntStr(funcIndex));
end;

procedure WasmDrop;
begin
  WasmBodyB($1A); WasmText('drop');
end;

procedure WasmReturn;
begin
  WasmBodyB($0F); WasmText('return');
end;

{ `unreachable` traps. It is also POLYMORPHIC in wasm's type system — it
  satisfies any expected result type — which is what lets a not-yet-lowered
  body be a single one of these regardless of the function's signature. }
procedure WasmBodyUnreachable;
begin
  WasmBodyB($00); WasmText('unreachable');
end;

{ The body's trailing `end`. Emitted into the binary; the text form gets its
  closing paren from asmtext_wasm.inc instead, so nothing is written here. }
procedure WasmBodyTerminate;
begin
  WasmBodyB(WOP_END);
end;

{ Seal the scratch body into the code pool for a function slot. }
procedure WasmBodyEnd(slot: Integer);
var i: Integer;
begin
  WasmFuncText[slot] := WFText;
  if WasmCodeLen + WFBLen > MAX_WASM_CODE then WasmFail('wasm: code pool full');
  WasmFuncCodeOfs[slot] := WasmCodeLen;
  WasmFuncCodeLen[slot] := WFBLen;
  for i := 0 to WFBLen - 1 do
  begin
    WasmCodePool[WasmCodeLen] := WFB[i];
    Inc(WasmCodeLen);
  end;
  WFBLen := 0;
end;

{ ===== module output primitives ===== }

procedure WOutB(b: Byte);
begin
  if WBLen >= MAX_WASM_BYTES then WasmFail('wasm: module output too large');
  WB[WBLen] := b;
  Inc(WBLen);
end;

procedure WOutU32(v: Int64);
var x: Int64; b: Byte;
begin
  x := v;
  repeat
    b := Byte(x and $7F);
    x := x shr 7;
    if x <> 0 then b := b or $80;
    WOutB(b);
  until x = 0;
end;

{ Signed LEB128 into the module buffer. Pascal's shr on Int64 is LOGICAL, so
  the arithmetic shift the encoding needs is done by hand. }
procedure WOutS32(v: Int64);
var x: Int64; b: Byte; more: Boolean;
begin
  x := v;
  more := True;
  while more do
  begin
    b := Byte(x and $7F);
    x := x shr 7;
    if v < 0 then x := x or (Int64(-1) shl 57);
    if ((x = 0) and ((b and $40) = 0)) or ((x = -1) and ((b and $40) <> 0)) then
      more := False
    else
      b := b or $80;
    WOutB(b);
  end;
end;

procedure WOutBytes(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do WOutB(Byte(s[i]));
end;

procedure WOutName(const s: AnsiString);
begin
  WOutU32(Length(s));
  WOutBytes(s);
end;

{ Write a 5-byte padded LEB128 placeholder and return its position. }
function WOutSizePlaceholder: Integer;
var i: Integer;
begin
  WOutSizePlaceholder := WBLen;
  for i := 1 to 5 do WOutB(0);
end;

{ Patch a placeholder with `size`, keeping the full 5 bytes. Non-minimal but
  legal, and it is what removes the need for a section-sized scratch buffer. }
procedure WPatchSize(pos, size: Integer);
var i: Integer; x: Int64; b: Byte;
begin
  x := size;
  for i := 0 to 4 do
  begin
    b := Byte(x and $7F);
    x := x shr 7;
    if i < 4 then b := b or $80;
    WB[pos + i] := b;
  end;
end;

{ ===== section emission ===== }

procedure WasmEmitTypeSection;
var i, j, p: Integer;
begin
  if WasmTypeCount = 0 then Exit;
  WOutB(WSEC_TYPE);
  p := WOutSizePlaceholder;
  WOutU32(WasmTypeCount);
  for i := 0 to WasmTypeCount - 1 do
  begin
    WOutB($60);                       { func type }
    WOutU32(WasmTypeNPar[i]);
    for j := 0 to WasmTypeNPar[i] - 1 do WOutB(WasmSigPool[WasmTypeParOfs[i] + j]);
    WOutU32(WasmTypeNRes[i]);
    for j := 0 to WasmTypeNRes[i] - 1 do WOutB(WasmSigPool[WasmTypeResOfs[i] + j]);
  end;
  WPatchSize(p, WBLen - p - 5);
end;

procedure WasmEmitImportSection;
var i, p: Integer;
begin
  if WasmImpCount = 0 then Exit;
  WOutB(WSEC_IMPORT);
  p := WOutSizePlaceholder;
  WOutU32(WasmImpCount);
  for i := 0 to WasmImpCount - 1 do
  begin
    WOutName(WasmImpModule[i]);
    WOutName(WasmImpName[i]);
    WOutB(Byte(WasmImpKind[i]));
    if WasmImpKind[i] = WEK_FUNC then
      WOutU32(WasmImpType[i])
    else
      WasmFail('wasm: only function imports are supported in v1');
  end;
  WPatchSize(p, WBLen - p - 5);
end;

procedure WasmEmitFuncSection;
var i, p: Integer;
begin
  if WasmFuncCount = 0 then Exit;
  WOutB(WSEC_FUNC);
  p := WOutSizePlaceholder;
  WOutU32(WasmFuncCount);
  for i := 0 to WasmFuncCount - 1 do WOutU32(WasmFuncType[i]);
  WPatchSize(p, WBLen - p - 5);
end;

procedure WasmEmitMemorySection;
var p: Integer;
begin
  if not WasmMemPresent then Exit;
  WOutB(WSEC_MEM);
  p := WOutSizePlaceholder;
  WOutU32(1);
  if WasmMemMax >= 0 then
  begin
    WOutB(1);                       { limits: min and max }
    WOutU32(WasmMemMin);
    WOutU32(WasmMemMax);
  end
  else
  begin
    WOutB(0);                       { limits: min only }
    WOutU32(WasmMemMin);
  end;
  WPatchSize(p, WBLen - p - 5);
end;

procedure WasmEmitGlobalSection;
var i, p: Integer;
begin
  if WasmGlobCount = 0 then Exit;
  WOutB(WSEC_GLOBAL);
  p := WOutSizePlaceholder;
  WOutU32(WasmGlobCount);
  for i := 0 to WasmGlobCount - 1 do
  begin
    WOutB(WasmGlobType[i]);
    if WasmGlobMut[i] then WOutB(1) else WOutB(0);
    { init expr — a single typed constant, then end }
    if WasmGlobType[i] = WT_I64 then
      WOutB(WOP_I64_CONST)
    else
      WOutB(WOP_I32_CONST);
    WOutS32(WasmGlobInit[i]);
    WOutB(WOP_END);
  end;
  WPatchSize(p, WBLen - p - 5);
end;

procedure WasmEmitExportSection;
var i, p: Integer;
begin
  if WasmExpCount = 0 then Exit;
  WOutB(WSEC_EXPORT);
  p := WOutSizePlaceholder;
  WOutU32(WasmExpCount);
  for i := 0 to WasmExpCount - 1 do
  begin
    WOutName(WasmExpName[i]);
    WOutB(Byte(WasmExpKind[i]));
    WOutU32(WasmExpIdx[i]);
  end;
  WPatchSize(p, WBLen - p - 5);
end;

{ The code section. Each entry is size(locals + body); the locals vector is
  run-length compressed from the flat per-local pool. }
procedure WasmEmitCodeSection;
var i, j, p, bp, runStart, groups: Integer; vt: Byte;
begin
  if WasmFuncCount = 0 then Exit;
  WOutB(WSEC_CODE);
  p := WOutSizePlaceholder;
  WOutU32(WasmFuncCount);
  for i := 0 to WasmFuncCount - 1 do
  begin
    bp := WOutSizePlaceholder;
    { count run-length groups first — the vector needs its length up front }
    groups := 0; j := 0;
    while j < WasmFuncNLoc[i] do
    begin
      vt := WasmLocalPool[WasmFuncLocOfs[i] + j];
      runStart := j;
      while (j < WasmFuncNLoc[i]) and
            (WasmLocalPool[WasmFuncLocOfs[i] + j] = vt) do Inc(j);
      if j > runStart then Inc(groups);
    end;
    WOutU32(groups);
    j := 0;
    while j < WasmFuncNLoc[i] do
    begin
      vt := WasmLocalPool[WasmFuncLocOfs[i] + j];
      runStart := j;
      while (j < WasmFuncNLoc[i]) and
            (WasmLocalPool[WasmFuncLocOfs[i] + j] = vt) do Inc(j);
      WOutU32(j - runStart);
      WOutB(vt);
    end;
    for j := 0 to WasmFuncCodeLen[i] - 1 do
      WOutB(WasmCodePool[WasmFuncCodeOfs[i] + j]);
    WPatchSize(bp, WBLen - bp - 5);
  end;
  WPatchSize(p, WBLen - p - 5);
end;

{ ===== the whole module ===== }

procedure WasmEmitModule;
begin
  WBLen := 0;
  WOutB($00); WOutB($61); WOutB($73); WOutB($6D);   { \0asm }
  WOutB($01); WOutB($00); WOutB($00); WOutB($00);   { version 1 }
  { Section ORDER is normative — a validator rejects them out of order. }
  WasmEmitTypeSection;
  WasmEmitImportSection;
  WasmEmitFuncSection;
  WasmEmitMemorySection;
  WasmEmitGlobalSection;
  WasmEmitExportSection;
  WasmEmitCodeSection;
end;

{ Binary output goes through the house sysopen/syswrite/sysfchmod/sysclose
  intrinsics, the same path writeELF uses — the dialect has no untyped `file`
  and no BlockWrite. They are compiler INTRINSICS (tkSysOpen &c), not library
  functions, so they are reachable from a standalone program too, which is what
  lets this file be exercised without being included into compiler.pas.
  A .wasm is not executable, so it is chmod 0644 rather than writeELF's 0755. }
procedure WasmSaveModule(const path: AnsiString);
var f, n: Integer; p: AnsiString;
begin
  WasmEmitModule;
  p := path;
  f := sysopen(p, 577);        { O_WRONLY | O_CREAT | O_TRUNC }
  if f < 0 then WasmFail('wasm: cannot open ' + path + ' for writing');
  if WBLen > 0 then
  begin
    n := syswrite(f, WB[0], WBLen);
    if n <> WBLen then WasmFail('wasm: short write to ' + path);
  end;
  sysfchmod(f, 420);           { 0644 — a module is data, not an executable }
  sysclose(f);
end;

{ ===== the compiler-facing entry point =====

  Called from compiler.pas's output-writer dispatch, in place of the
  registration-era Error. It is deliberately GUARDED: with no codegen the
  module model is empty, and writing an empty-but-valid .wasm for a program
  that plainly has code would be a silently wrong output — the exact failure
  class this project treats as the expensive one. Until ir_codegen_wasm32.inc
  populates the model (Phase 2), every real program takes the Error branch, and
  it takes it for an accurate reason. }
{ Body in ir_codegen_wasm32.inc, which is included later (with the other
  backends) than this file (with the other encoders). Forwarded here rather
  than in compiler.pas: the dependency is between two wasm files, so it should
  not cost a line in a shared one. }
procedure WasmReportCoverage; forward;

procedure writeWasm(const outPath: AnsiString);
begin
  WasmReportCoverage;
  if WasmFuncCount = 0 then
    WasmFail('wasm32: nothing to write — no code was generated for this module '
          + '(wasm codegen lands in Phase 2; the module writer is present and '
          + 'tested via test/wasm/check_phase1.sh)');
  WasmSaveModule(outPath);
end;
