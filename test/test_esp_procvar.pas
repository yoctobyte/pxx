{ SPDX-License-Identifier: MPL-2.0 }
program test_esp_procvar;
{ Indirect calls (IR_CALL_IND) on the bare ESP targets. The div-zero runtime
  (PXXDivZero, builtinheap.pas) calls through the PXXDivZeroHook proc var, so
  EVERY program pulls an indirect call since v135 -- this test exercises the
  riscv32/xtensa IR_CALL_IND lowering with real arguments and results too.
  See bug-esp-bare-riscv32-xtensa-cannot-compile-trivial-program. }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}

procedure PutIntRec(n: Integer);
begin
  if n >= 10 then PutIntRec(n div 10);
  PutC(48 + n mod 10);
end;

procedure PutInt(n: Integer);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  PutIntRec(n);
end;

type
  TBinOp = function(a, b: Integer): Integer;
  TNotify = procedure;

function AddOp(a, b: Integer): Integer;
begin
  AddOp := a + b;
end;

function MulOp(a, b: Integer): Integer;
begin
  MulOp := a * b;
end;

var Pinged: Integer;

procedure Ping;
begin
  Pinged := Pinged + 1;
end;

var
  f: TBinOp;
  n: TNotify;
begin
  f := @AddOp;
  PutInt(f(3, 4)); PutC(10);          { 7 }
  f := @MulOp;
  PutInt(f(3, 4)); PutC(10);          { 12 }
  n := @Ping;
  n(); n();
  PutInt(Pinged); PutC(10);           { 2 }
{$ifdef PXX_ESP} while True do ; {$endif}
end.
