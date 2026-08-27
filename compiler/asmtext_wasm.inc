{ SPDX-License-Identifier: MPL-2.0 }
{ asmtext_wasm.inc — WAT (WebAssembly text) emitter.

  Peer of asmtext_386.inc / asmtext_rv32.inc / asmtext_a64.inc: the readable
  form of what wasmenc.inc encodes. It renders the module STRUCTURE — types,
  imports, memory, globals, exports, function headers — and splices in the
  per-function instruction text that the instruction layer in wasmenc.inc built
  alongside the bytes. It never decodes an opcode, which is the point: there is
  one description of a body, not two that must be kept agreeing.

  Labels are NAMED ($L12), never numeric br depths — `br 3` is unreadable and
  readability is half of why this file exists (PLAN.md). }

function WasmValTypeName(vt: Byte): AnsiString;
begin
  if vt = WT_I32 then WasmValTypeName := 'i32'
  else if vt = WT_I64 then WasmValTypeName := 'i64'
  else if vt = WT_F32 then WasmValTypeName := 'f32'
  else if vt = WT_F64 then WasmValTypeName := 'f64'
  else if vt = WT_FUNCREF then WasmValTypeName := 'funcref'
  else WasmValTypeName := '?';
end;

{ The (param ...) (result ...) clause of a signature, as WAT. When `slot` names
  a defined function its parameter NAMES are used — one (param $x t) per
  parameter — so the body's `local.get $x` resolves. slot < 0 (an import, or a
  bare signature) falls back to the unnamed grouped form. }
function WasmSigTextFor(typeIdx, slot: Integer): AnsiString;
var j: Integer; r, nm: AnsiString;
begin
  r := '';
  if WasmTypeNPar[typeIdx] > 0 then
  begin
    if slot >= 0 then
      for j := 0 to WasmTypeNPar[typeIdx] - 1 do
      begin
        nm := '';
        if j < WasmFuncNVar[slot] then nm := WasmVarNames[WasmFuncVarOfs[slot] + j];
        if nm <> '' then
          r := r + ' (param $' + nm + ' '
               + WasmValTypeName(WasmSigPool[WasmTypeParOfs[typeIdx] + j]) + ')'
        else
          r := r + ' (param '
               + WasmValTypeName(WasmSigPool[WasmTypeParOfs[typeIdx] + j]) + ')';
      end
    else
    begin
      r := r + ' (param';
      for j := 0 to WasmTypeNPar[typeIdx] - 1 do
        r := r + ' ' + WasmValTypeName(WasmSigPool[WasmTypeParOfs[typeIdx] + j]);
      r := r + ')';
    end;
  end;
  if WasmTypeNRes[typeIdx] > 0 then
  begin
    r := r + ' (result';
    for j := 0 to WasmTypeNRes[typeIdx] - 1 do
      r := r + ' ' + WasmValTypeName(WasmSigPool[WasmTypeResOfs[typeIdx] + j]);
    r := r + ')';
  end;
  WasmSigTextFor := r;
end;

function WasmSigText(typeIdx: Integer): AnsiString;
begin
  WasmSigText := WasmSigTextFor(typeIdx, -1);
end;

function WasmExportKindName(k: Integer): AnsiString;
begin
  if k = WEK_FUNC then WasmExportKindName := 'func'
  else if k = WEK_TABLE then WasmExportKindName := 'table'
  else if k = WEK_MEM then WasmExportKindName := 'memory'
  else WasmExportKindName := 'global';
end;

{ The exported name of a function index, or '' — used to give an export its
  (export "x") clause inline on the func, which is how wasm2wat renders it. }
function WasmExportNameOf(kind, idx: Integer): AnsiString;
var i: Integer;
begin
  WasmExportNameOf := '';
  for i := 0 to WasmExpCount - 1 do
    if (WasmExpKind[i] = kind) and (WasmExpIdx[i] = idx) then
    begin
      WasmExportNameOf := WasmExpName[i];
      Exit;
    end;
end;

procedure WasmWriteText(const path: AnsiString);
var
  f: Text;
  i, j, gi: Integer;
  ex, loc, nm: AnsiString;
begin
  Assign(f, path);
  Rewrite(f);
  Writeln(f, '(module');

  { imports first — they define the low function index space }
  for i := 0 to WasmImpCount - 1 do
    Writeln(f, '  (import "', WasmImpModule[i], '" "', WasmImpName[i],
               '" (func $', WasmImpName[i], WasmSigText(WasmImpType[i]), '))');

  if WasmMemPresent then
  begin
    ex := WasmExportNameOf(WEK_MEM, 0);
    if ex <> '' then
      Write(f, '  (memory (export "', ex, '") ')
    else
      Write(f, '  (memory ');
    if WasmMemMax >= 0 then
      Writeln(f, WasmMemMin, ' ', WasmMemMax, ')')
    else
      Writeln(f, WasmMemMin, ')');
  end;

  for gi := 0 to WasmGlobCount - 1 do
  begin
    Write(f, '  (global $', WasmGlobName[gi]);
    ex := WasmExportNameOf(WEK_GLOBAL, gi);
    if ex <> '' then Write(f, ' (export "', ex, '")');
    if WasmGlobMut[gi] then
      Write(f, ' (mut ', WasmValTypeName(WasmGlobType[gi]), ')')
    else
      Write(f, ' ', WasmValTypeName(WasmGlobType[gi]));
    if WasmGlobType[gi] = WT_I64 then
      Writeln(f, ' (i64.const ', WasmGlobInit[gi], '))')
    else
      Writeln(f, ' (i32.const ', WasmGlobInit[gi], '))');
  end;

  for i := 0 to WasmFuncCount - 1 do
  begin
    Write(f, '  (func $', WasmFuncName[i]);
    ex := WasmExportNameOf(WEK_FUNC, WasmFuncIndex(i));
    if ex <> '' then Write(f, ' (export "', ex, '")');
    Write(f, WasmSigTextFor(WasmFuncType[i], i));
    Writeln(f);
    { locals, one declaration per local — the binary side run-length compresses
      them, the text side does not need to and is clearer without it }
    for j := 0 to WasmFuncNLoc[i] - 1 do
    begin
      loc := WasmValTypeName(WasmLocalPool[WasmFuncLocOfs[i] + j]);
      { locals follow the params in the index space }
      nm := '';
      if WasmTypeNPar[WasmFuncType[i]] + j < WasmFuncNVar[i] then
        nm := WasmVarNames[WasmFuncVarOfs[i] + WasmTypeNPar[WasmFuncType[i]] + j];
      if nm <> '' then
        Writeln(f, '    (local $', nm, ' ', loc, ')')
      else
        Writeln(f, '    (local ', loc, ')');
    end;
    Write(f, WasmFuncText[i]);
    Writeln(f, '  )');
  end;

  { any export that was not rendered inline above }
  for i := 0 to WasmExpCount - 1 do
    if WasmExpKind[i] = WEK_TABLE then
      Writeln(f, '  (export "', WasmExpName[i], '" (',
                 WasmExportKindName(WasmExpKind[i]), ' ', WasmExpIdx[i], '))');

  Writeln(f, ')');
  Close(f);
end;
