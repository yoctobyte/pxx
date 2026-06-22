program test_esp_varparam;
{ riscv32 var->var forwarding (feature-riscv32-var-param-forwarding): a var
  parameter forwarded into another routine's var parameter. Output via the same
  UART/oracle scaffold as test_esp_bare; the esp32c3 (riscv32) UART must match the
  x86-64 oracle. direct= and fwd= must both be 3333. }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
{$else}
{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure PutC(code: Integer);
begin
  esp_rom_printf('%c', code);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}
{$endif}

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

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

procedure inner(var p: Integer);
begin
  p := 3333;
end;

procedure outer(var op: Integer);
begin
  inner(op);             { var op forwarded to inner's var p }
end;

var x: Integer;
begin
  x := 0; inner(x); PutS('direct='); PutInt(x); PutC(10);
  x := 0; outer(x); PutS('fwd=');    PutInt(x); PutC(10);
{$ifdef PXX_ESP} while True do ; {$endif}
end.
