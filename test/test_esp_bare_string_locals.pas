program test_esp_bare_string_locals;
{ SCALAR AnsiString locals released at scope exit, on the bare ESP profile.

  test_esp_bare_managed.pas covers managed RECORDS and has ZERO scalar-string
  release sites, so the SXR_STR arm — the one the inline nil test touches on
  every backend — was not exercised by any bare fixture at all. Measured
  2026-09-22 while landing that arm on xtensa: all three bare fixtures in the
  tree emitted 0 `beqz a2` sites, which is a suite avoiding the shape rather
  than evidence about it.

  It exercises BOTH sides of the nil test deliberately: a local that is
  assigned (non-nil at scope exit, so the branch is NOT taken and the release
  runs) and a local that is never assigned (nil, branch taken, release
  skipped). A fixture with only assigned locals would pass identically with
  the branch inverted.

  Same PutC/PutS scaffolding as test_esp_bare_managed.pas: UART0 MMIO on bare,
  a raw write syscall on the oracle, so the same source runs on x86-64 and the
  serial bytes must match. perf-a-every-return-releases-every-managed-local }

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

procedure PutI(n: Integer);
var d: array[0..11] of Integer; k: Integer;
begin
  if n = 0 then begin PutC(48); Exit; end;
  k := 0;
  while n > 0 do begin d[k] := n mod 10; n := n div 10; Inc(k); end;
  while k > 0 do begin Dec(k); PutC(48 + d[k]); end;
end;

{ EVERY local assigned: the nil test falls through and the release runs on all
  four. Heap-allocated, so a missed release is a leak and a double release
  corrupts — neither of which a value check would see, which is why the count
  below is the assertion. }
function AllLive(n: Integer): Integer;
var a, b, c, d: AnsiString;
begin
  a := 'aa'; b := a + 'bb'; c := b + 'cc'; d := c + 'dd';
  AllLive := Length(a) + Length(b) + Length(c) + Length(d) + n;
end;

{ NONE assigned: all four are nil at scope exit and the branch is taken every
  time. This is the arm the whole change exists for, and it is the arm a
  fixture written the ordinary way would not contain. }
function NoneLive(n: Integer): Integer;
var a, b, c, d: AnsiString;
begin
  NoneLive := Length(a) + Length(b) + Length(c) + Length(d) + n;
end;

{ MIXED, with the live one LAST — the position the rules file says to put the
  interesting element in, because a sweep that stops at the first nil would
  still pass with it first. }
function MixedLiveLast(n: Integer): Integer;
var a, b, c, d: AnsiString;
begin
  d := 'zz';
  MixedLiveLast := Length(a) + Length(b) + Length(c) + Length(d) + n;
end;

var i, acc: Integer;
begin
  acc := 0;
  for i := 1 to 50 do
  begin
    acc := acc + AllLive(0);
    acc := acc + NoneLive(0);
    acc := acc + MixedLiveLast(0);
  end;
  PutS('acc='); PutI(acc); PutC(10);
  PutS('strlocals ok'); PutC(10);
end.
