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

{ Output goes through sysopen/syswrite/sysfchmod/sysclose, exactly as
  WriteMapFile (asmdisasm_x64.inc) and writeELF do — 20 sites in the compiler
  use this path and none uses Text.

  This file's first draft used `var f: Text` + Assign/Rewrite/Writeln/Close and
  failed to self-host with `undefined variable (Close)`. That looks like an RTL
  gap and is NOT one, so the reason is written down here rather than left to be
  rediscovered and mis-filed:

    - The RTL supports Text I/O perfectly well; a standalone pxx program does
      Assign/Rewrite/Writeln/Close and writes its file.
    - `pasparser_prog.inc:651` pulls that surface in implicitly when the token
      stream mentions Text/TextFile/IOResult/Flush — but only `if (not
      NoDefaultRtl)`.
    - `compiler.pas:19` is `{$define PXX_NODEFAULTRTL}`.

  So the compiler DELIBERATELY opts out of the default RTL surface, and Text
  file I/O is absent by design rather than missing by omission. The
  sysopen/syswrite form is therefore the platonic one *for compiler-internal
  output* — not a workaround standing in for idiomatic code, and nothing to
  file a bug against. The idiomatic-FPC form is the right one on the other side
  of that boundary, which is where the RTL lives.

  Lines accumulate in a buffer and flush in blocks so a large module is not one
  syscall per line. }
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

{ One byte as exactly two lowercase hex digits — a WAT string escape is
  `\HH` and a single digit is a syntax error, so the leading zero is not
  cosmetic. }
function WasmHex2(b: Byte): AnsiString;
const HEXD: AnsiString = '0123456789abcdef';
begin
  WasmHex2 := HEXD[(b shr 4) + 1] + HEXD[(b and $0F) + 1];
end;

procedure WasmWriteText(const path: AnsiString);
var
  i, j, gi: Integer;
  loc, nm: AnsiString;
begin
  WTFd := sysopen(path, 577);        { O_WRONLY | O_CREAT | O_TRUNC }
  if WTFd < 0 then WasmFail('wasm: cannot open ' + path + ' for writing');
  sysfchmod(WTFd, 420);              { chmod 644 }
  WTLen := 0;

  WTLn('(module');

  { EVERY function type, declared explicitly and in our order, before anything
    that uses one.

    The inline `(param ...) (result ...)` forms below are an abbreviation: a
    parser resolves each to the first DECLARED type that matches, appending a
    new one only if none does. So declaring the whole table up front makes the
    text's type numbering identical to the binary's by construction — where
    before it was identical by coincidence, because the two happened to
    interleave in the same order.

    The coincidence broke on the first module with an import. An import must
    precede the functions in the text, so its inline signature became the
    parser's type 0, while in the binary it was interned wherever
    WasmSigForProc reached it — and every `call_indirect (type N)`, which
    carries a NUMBER, then named a different signature in the two modules. The
    oracle caught it as a wall of type mismatches; nothing else would have. }
  for i := 0 to WasmTypeCount - 1 do
    WTLn('  (type (func' + WasmSigText(i) + '))');

  { imports next — they define the low function index space }
  for i := 0 to WasmImpCount - 1 do
    WTLn('  (import "' + WasmImpModule[i] + '" "' + WasmImpName[i]
         + '" (func $' + WasmImpName[i] + WasmSigText(WasmImpType[i]) + '))');

  if WasmMemPresent then
  begin
    WT('  (memory ');
    if WasmMemMax >= 0 then
      WTLn(WasmIntTxt(WasmMemMin) + ' ' + WasmIntTxt(WasmMemMax) + ')')
    else
      WTLn(WasmIntTxt(WasmMemMin) + ')');
  end;

  { The function table and its one element segment. Numeric function indices
    rather than $names: the element list already holds indices (imports
    included), and rendering them as names would mean inventing the mapping a
    second time — the WAT is an oracle for the binary, so it says what the
    binary says. Slot 0 is skipped; the segment starts at 1. }
  if WasmTabCount > 0 then
  begin
    WTLn('  (table ' + WasmIntTxt(WasmTabCount + 1) + ' funcref)');
    WT('  (elem (i32.const 1)');
    { Slots, biased past the imports — the same close the binary does. }
    for i := 0 to WasmTabCount - 1 do
      WT(' ' + WasmIntTxt(WasmIndexOfSlot(WasmTabElem[i])));
    WTLn(')');
  end;

  for gi := 0 to WasmGlobCount - 1 do
  begin
    WT('  (global $' + WasmGlobName[gi]);
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

  { The data segment, every byte as \HH. Escaping unconditionally rather than
    passing printable ASCII through is the difference between an oracle and a
    quoting bug: a blob holds string literals AND raw structure bytes, and the
    ones that would need escaping anyway (quote, backslash, newline) are
    exactly the ones a literal is most likely to contain. }
  if WasmDataSegLen > 0 then
  begin
    WT('  (data (i32.const ' + WasmIntTxt(WasmDataSegBase) + ') "');
    for i := 0 to WasmDataSegLen - 1 do
      WT('\' + WasmHex2(WasmDataSeg[i]));
    WTLn('")');
  end;

  { EVERY export, as its own form, in the order the export table holds them —
    not as an inline attribute on the func/global/memory it names.

    Inline is the idiomatic WAT and it was wrong here for a reason worth
    keeping: an inline export is emitted where its TARGET sits, so the text's
    export order follows function order while the binary's follows insertion
    order. The two modules were identical in every way a program can observe
    and differed in the one way the oracle compares them, which cost a
    debugging session that started out looking like a missing export. An
    oracle should mirror the structure it is checking, not the prettier
    spelling of it. }
  for i := 0 to WasmExpCount - 1 do
    WTLn('  (export "' + WasmExpName[i] + '" ('
         + WasmExportKindName(WasmExpKind[i]) + ' '
         + WasmIntTxt(WasmExportIndex(i)) + '))');

  WTLn(')');
  WTFlush;
  sysclose(WTFd);
end;
