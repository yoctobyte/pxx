program test_esp_exception;
{ try/except/finally on the bare ESP targets (feature-esp-bare-exceptions):
  the riscv32 setjmp/longjmp exception frames, reused on the bare profile,
  and the xtensa Call0 mirror (jmpbuf = a15, sp, a0). The x86-64 oracle runs
  the same source over a write(2) syscall, so the serial bytes must match
  byte-for-byte. }

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

procedure PutIntRec(n: Integer);
begin
  if n >= 10 then PutIntRec(n div 10);
  PutC(48 + n mod 10);
end;

procedure PutInt(n: Integer);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  PutIntRec(n); PutC(10);
end;

procedure Fail(val: Integer);
begin
  raise val;
  PutInt(999);
end;

procedure TestExcept;
begin
  try
    PutInt(1);
    Fail(42);
    PutInt(999);
  except
    PutInt(2);
  end;
end;

procedure TestFinally;
begin
  try
    PutInt(3);
    try
      PutInt(4);
      Fail(100);
      PutInt(999);
    finally
      PutInt(5);
    end;
  except
    PutInt(6);
  end;
end;

procedure TestReraise;
begin
  try
    try
      Fail(77);
    except
      PutInt(7);
      raise;
    end;
  except
    PutInt(8);
  end;
end;

procedure TestNestedNormal;
begin
  try
    try
      PutInt(9);
    finally
      PutInt(10);
    end;
    PutInt(11);
  except
    PutInt(999);
  end;
end;

begin
  TestExcept;
  TestFinally;
  TestReraise;
  TestNestedNormal;
  PutInt(12);
{$ifdef PXX_ESP} while True do ; {$endif}
end.
