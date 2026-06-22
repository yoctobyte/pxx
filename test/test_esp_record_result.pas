program test_esp_record_result;
{ riscv32 record copy + by-value record function results
  (feature-riscv32-record-function-results). Record assignment (IR_COPY_REC) and
  returning a record by value (hidden-destination ABI, t1) were both missing on
  riscv32. Output via the test_esp_bare UART/oracle scaffold; esp32c3 (riscv32)
  must match the x86-64 oracle. Covers: record copy, a 2-field by-value result
  (net.pas's TNetAddress shape), and a 5-field (>2 word) result. Output:
  11 / 22 / 2130706433 / 8080 / 150.
  Runs on esp32c3 (riscv32) AND esp32s3 (xtensa Call0). Xtensa WINDOWED record
  results stay unsupported (no clean hidden-dest register across the call-window
  rotation) and are rejected at the callee epilogue. }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
procedure PutC(code: Integer);
begin PByte(Int64($60000000))^ := Byte(code); end;
{$else}
{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure PutC(code: Integer);
begin esp_rom_printf('%c', code); end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin b := code; r := __pxxrawsyscall(1, 1, Int64(@b), 1); end;
{$endif}
{$endif}

procedure PutIntRec(n: Integer);
begin if n >= 10 then PutIntRec(n div 10); PutC(48 + n mod 10); end;

procedure PutInt(n: Integer);
begin if n < 0 then begin PutC(45); n := -n; end; PutIntRec(n); PutC(10); end;

type
  TR = record a, b: Integer; end;
  TNetAddress = record Host: LongWord; Port: Integer; end;
  TBig = record a, b, c, d, e: Integer; end;

function MkNet(h: LongWord; p: Integer): TNetAddress;
begin Result.Host := h; Result.Port := p; end;

function MkBig(x: Integer): TBig;
begin Result.a := x; Result.b := x*2; Result.c := x*3; Result.d := x*4; Result.e := x*5; end;

var
  r, r2: TR;
  n: TNetAddress;
  big: TBig;
begin
  r.a := 11; r.b := 22;
  r2 := r;                                  { record copy }
  PutInt(r2.a); PutInt(r2.b);               { 11 22 }
  n := MkNet(2130706433, 8080);             { 2-word by-value result }
  PutInt(Integer(n.Host)); PutInt(n.Port);  { 2130706433 8080 }
  big := MkBig(10);                         { 5-word by-value result }
  PutInt(big.a + big.b + big.c + big.d + big.e);   { 150 }
{$ifdef PXX_ESP} while True do ; {$endif}
end.
