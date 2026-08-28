{ SPDX-License-Identifier: MPL-2.0 }
{ Phase 1 self-test: build a module by hand through wasmenc.inc's model, write
  both the .wasm and the .wat, and let the harness prove they describe the same
  module. Standalone on purpose — it includes the two new files directly rather
  than going through compiler.pas, so Phase 1 is provable before the branch
  touches a shared file. }
program WasmEncSelfTest;

{$define WASMENC_STANDALONE}
{$include ../../compiler/wasmenc.inc}
{$include ../../compiler/asmtext_wasm.inc}

var
  tVoidI32, tI32I32_I32, tVoid: Integer;
  lFp: Integer;
  fPrint, fAddMul, fMain: Integer;
  gSp: Integer;
  outBase: AnsiString;

begin
  if ParamCount < 1 then
  begin
    Writeln('usage: wasmenc_selftest <output-basename>');
    Halt(2);
  end;
  outBase := ParamStr(1);

  WasmReset;

  { signatures }
  tVoidI32    := WasmAddType([WT_I32], []);              { (i32) -> ()   }
  tI32I32_I32 := WasmAddType([WT_I32, WT_I32], [WT_I32]);{ (i32,i32)->i32 }
  tVoid       := WasmAddType([], []);                    { () -> ()      }

  { the host print import — occupies function index 0 }
  fPrint := WasmAddImportFunc('env', 'print', tVoidI32);

  { one page of linear memory, exported so a harness can inspect it }
  WasmSetMemory(1, -1);
  WasmAddExport('memory', WEK_MEM, 0);

  { the shadow-stack pointer, exported so the harness can assert it balances }
  gSp := WasmAddGlobal('sp', WT_I32, True, 65536);
  WasmAddExport('sp', WEK_GLOBAL, gSp);

  { addmul(a, b) = (a + b) * 2, computed THROUGH linear memory so the store/load
    path and the i32.load/i32.store encodings are exercised, not just arithmetic }
  fAddMul := WasmAddFunc('addmul', tI32I32_I32);
  WasmBodyBegin;
  WasmAddParamName('a');
  WasmAddParamName('b');
  lFp := WasmAddLocal(WT_I32, 'fp');
    { $fp := $sp - 16 ; $sp := $fp }
    WasmGlobalGet(gSp);
    WasmI32Const(16);
    WasmOp($6B, 'i32.sub');
    WasmLocalSet(lFp);
    WasmLocalGet(lFp);
    WasmGlobalSet(gSp);
    { [fp+0] := a + b }
    WasmLocalGet(lFp);
    WasmLocalGet(0);
    WasmLocalGet(1);
    WasmOp($6A, 'i32.add');
    WasmI32Store(2, 0);
    { result := [fp+0] * 2 }
    WasmLocalGet(lFp);
    WasmI32Load(2, 0);
    WasmI32Const(2);
    WasmOp($6C, 'i32.mul');
    { $sp := $fp + 16  — restore, so the harness's balance assertion means something }
    WasmLocalGet(lFp);
    WasmI32Const(16);
    WasmOp($6A, 'i32.add');
    WasmGlobalSet(gSp);
    WasmBodyTerminate;
  WasmBodyEnd(fAddMul);

  { main: print a few values chosen to exercise LEB128 rather than arithmetic }
  fMain := WasmAddFunc('main', tVoid);
  WasmBodyBegin;
    { 14 — the Phase 0 probe's answer, now produced by our own encoder }
    WasmI32Const(3);
    WasmI32Const(4);
    WasmCall(WasmFuncIndex(fAddMul), 'addmul');
    WasmCall(fPrint, 'print');
    { signed LEB128, one byte, sign bit set }
    WasmI32Const(-1);
    WasmCall(fPrint, 'print');
    { signed LEB128 across the 7-bit boundary in both directions }
    WasmI32Const(-64);
    WasmCall(fPrint, 'print');
    WasmI32Const(-65);
    WasmCall(fPrint, 'print');
    WasmI32Const(63);
    WasmCall(fPrint, 'print');
    WasmI32Const(64);
    WasmCall(fPrint, 'print');
    { multi-byte unsigned and the 32-bit extremes }
    WasmI32Const(123456789);
    WasmCall(fPrint, 'print');
    WasmI32Const(-2147483648);
    WasmCall(fPrint, 'print');
    WasmI32Const(2147483647);
    WasmCall(fPrint, 'print');
    WasmBodyTerminate;
  WasmBodyEnd(fMain);

  WasmAddExport('main', WEK_FUNC, WasmFuncIndex(fMain));

  WasmSaveModule(outBase + '.wasm');
  WasmWriteText(outBase + '.wat');
  Writeln('wrote ', outBase, '.wasm (', WBLen, ' bytes) and ', outBase, '.wat');
end.
