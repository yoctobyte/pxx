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

{ Output goes through sysopen/syswrite/sysfchmod/sysclose, exactly as
  WriteMapFile (asmdisasm_x64.inc) and writeELF do. The compiler has no Text
  file I/O — Assign/Rewrite/Close are RTL, not compiler, and the first draft of
  this file used them and failed to self-host. Lines accumulate in a buffer and
  flush in blocks so a large module is not one syscall per line. }
const
  WT_CAP = 32768;

var
  WTFd    : Integer;
  WTChars : array[0..WT_CAP-1] of Char;
  WTLen   : Integer;

procedure WTFlush;
begin
  if WTLen > 0 then
  begin
    syswrite(WTFd, WTChars, WTLen);
    WTLen := 0;
  end;
end;

{ Append. A dedicated char buffer rather than the compiler's shared TokChars
  (which DisWriteStr borrows): borrowing global scratch is a hidden coupling,
  and TokChars does not exist in the standalone self-test build at all. }
procedure WT(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do
  begin
    if WTLen >= WT_CAP then WTFlush;
    WTChars[WTLen] := s[i];
    Inc(WTLen);
  end;
end;

procedure WTLn(const s: AnsiString);
begin
  WT(s + Chr(10));
end;

function WasmIntTxt(v: Int64): AnsiString;
var s: AnsiString;
begin
  Str(v, s);
  WasmIntTxt := s;
end;

procedure WasmWriteText(const path: AnsiString);
var
  i, j, gi: Integer;
  ex, loc, nm: AnsiString;
begin
  WTFd := sysopen(path, 577);        { O_WRONLY | O_CREAT | O_TRUNC }
  if WTFd < 0 then WasmFail('wasm: cannot open ' + path + ' for writing');
  sysfchmod(WTFd, 420);              { chmod 644 }
  WTLen := 0;

  WTLn('(module');

  { imports first — they define the low function index space }
  for i := 0 to WasmImpCount - 1 do
    WTLn('  (import "' + WasmImpModule[i] + '" "' + WasmImpName[i]
         + '" (func $' + WasmImpName[i] + WasmSigText(WasmImpType[i]) + '))');

  if WasmMemPresent then
  begin
    ex := WasmExportNameOf(WEK_MEM, 0);
    if ex <> '' then WT('  (memory (export "' + ex + '") ')
    else WT('  (memory ');
    if WasmMemMax >= 0 then
      WTLn(WasmIntTxt(WasmMemMin) + ' ' + WasmIntTxt(WasmMemMax) + ')')
    else
      WTLn(WasmIntTxt(WasmMemMin) + ')');
  end;

  for gi := 0 to WasmGlobCount - 1 do
  begin
    WT('  (global $' + WasmGlobName[gi]);
    ex := WasmExportNameOf(WEK_GLOBAL, gi);
    if ex <> '' then WT(' (export "' + ex + '")');
    if WasmGlobMut[gi] then
      WT(' (mut ' + WasmValTypeName(WasmGlobType[gi]) + ')')
    else
      WT(' ' + WasmValTypeName(WasmGlobType[gi]));
    if WasmGlobType[gi] = WT_I64 then
      WTLn(' (i64.const ' + WasmIntTxt(WasmGlobInit[gi]) + '))')
    else
      WTLn(' (i32.const ' + WasmIntTxt(WasmGlobInit[gi]) + '))');
  end;

  for i := 0 to WasmFuncCount - 1 do
  begin
    WT('  (func $' + WasmFuncName[i]);
    ex := WasmExportNameOf(WEK_FUNC, WasmFuncIndex(i));
    if ex <> '' then WT(' (export "' + ex + '")');
    WTLn(WasmSigTextFor(WasmFuncType[i], i));
    for j := 0 to WasmFuncNLoc[i] - 1 do
    begin
      loc := WasmValTypeName(WasmLocalPool[WasmFuncLocOfs[i] + j]);
      { locals follow the params in the index space }
      nm := '';
      if WasmTypeNPar[WasmFuncType[i]] + j < WasmFuncNVar[i] then
        nm := WasmVarNames[WasmFuncVarOfs[i] + WasmTypeNPar[WasmFuncType[i]] + j];
      if nm <> '' then WTLn('    (local $' + nm + ' ' + loc + ')')
      else WTLn('    (local ' + loc + ')');
    end;
    WT(WasmFuncText[i]);
    WTLn('  )');
  end;

  for i := 0 to WasmExpCount - 1 do
    if WasmExpKind[i] = WEK_TABLE then
      WTLn('  (export "' + WasmExpName[i] + '" ('
           + WasmExportKindName(WasmExpKind[i]) + ' '
           + WasmIntTxt(WasmExpIdx[i]) + '))');

  WTLn(')');
  WTFlush;
  sysclose(WTFd);
end;
