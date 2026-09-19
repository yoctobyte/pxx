program test_esp_idf_nested_try;
{ Exception frames that are NESTED -- two or more live at once in one body --
  on the windowed xtensa ABI (ESP32-S3 under ESP-IDF), with the x86-64 run as
  the oracle. Every row raises to an OUTER handler after something in the inner
  region used the expression stack or passed argument words past six, because
  that is what used to break: windowed frames were pushed by moving sp, the
  body's spills and outgoing arguments are sp-relative at fixed offsets, and
  with two frames pushed the first spill overwrote the outer frame's saved
  EXC_TOP link. The next raise that had to reach the outer handler faulted
  (LoadProhibited). Row 1 is the measured reproducer; a one- or two-word call
  in its place passed, which is why nothing caught it.

  EVERY ROW RAISES THROUGH THE LINK, NOT JUST NEAR IT. The first draft of this
  test passed on the unfixed compiler: a corrupted link only bites a raise that
  has to CROSS it to reach a frame still live further out, and each row's raise
  had a nearer handler. So each routine returns normally inside the caller's
  try, and the caller raises.
  See XtensaExcFrameAddrW (compiler/ir_codegen_xtensa.inc). }
{$mode objfpc}
uses sysutils;

{$ifdef CPU_XTENSA}{$define TEST_ON_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define TEST_ON_ESP}{$endif}

{$ifdef TEST_ON_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;

procedure Say(tag, v: Integer);
begin
  esp_rom_printf('T%d ', tag);
  esp_rom_printf('%d'#10, v);
end;
{$else}
procedure Say(tag, v: Integer);
begin
  WriteLn('T', tag, ' ', v);
end;
{$endif}

function Sum3(a, b, c: Integer): Integer;
begin
  Result := a + b + c;
end;

function Sum4L(a, b, c, d: Int64): Int64;
begin
  Result := a + b + c + d;
end;

{ ten argument words: four travel past the register set }
function Sum5L(a, b, c, d, e: Int64): Int64;
begin
  Result := a + b + c + d + e;
end;

var r: Int64;

{ 1. the reproducer: a managed local (the proc cleanup frame) plus a try whose
     body spills -- two frames live in one body. It returns normally, and the
     CALLER then raises to its own handler, which walks the link the spill hit. }
procedure InnerSpill(const t: AnsiString);
var s: AnsiString;
begin
  s := t + '!';
  try
    r := Sum4L(1, 2, Length(s), 3);
  except
    Say(99, 1);
  end;
end;

{ 2. two tries nested in ONE body; the inner one's call passes argument words
     past six, then the raise is caught by the outer one }
function NestedOverflow: Integer;
begin
  Result := 0;
  try
    try
      r := Sum5L(1, 2, 3, 4, 5);
    except
      Result := -1;
    end;
    raise Exception.Create('two');
  except
    Result := Result + Integer(r);
  end;
end;

{ 3. a managed local (proc cleanup frame) plus a try, exiting early from inside
     the try; the raise afterwards goes to the caller }
function ExitFromTry(n: Integer): Integer;
var s: AnsiString;
begin
  s := 'x' + IntToStr(n);
  try
    r := Sum4L(n, 2, 3, 4);
    if r > 0 then
    begin
      Result := Length(s);
      Exit;
    end;
  except
    Result := -2;
  end;
  Result := 0;
end;

{ 4. a try inside a finally, which reuses the depth the finally's region left }
function TryInFinally: Integer;
begin
  Result := 0;
  try
    Result := 1;
  finally
    try
      r := Sum5L(10, 20, 30, 40, 50);
      raise Exception.Create('four');
    except
      Result := Result + Integer(r);
    end;
  end;
end;

{ 5. every level holds a try around a spilling call; the bottom raises, the top
     catches -- the raise walks through every level's frame }
function Deep(n: Integer): Integer;
var s: AnsiString;
begin
  s := IntToStr(n);
  try
    r := Sum4L(n, n, n, Length(s));
    if n = 0 then raise Exception.Create('bottom');
    Result := Deep(n - 1) + 1;
  finally
    r := Sum3(n, 1, 1);
  end;
end;

begin
  try
    InnerSpill('ab');
    Say(1, Integer(r));
    raise Exception.Create('one');
  except
    Say(1, 100);
  end;
  try
    Say(2, NestedOverflow);
    raise Exception.Create('two, outer');
  except
    Say(2, 200);
  end;
  try
    Say(3, ExitFromTry(7));
    raise Exception.Create('three');
  except
    Say(3, 300);
  end;
  try
    Say(4, TryInFinally);
    raise Exception.Create('four, outer');
  except
    Say(4, 400);
  end;
  try
    Say(5, Deep(12));
  except
    Say(5, 500 + Integer(r));
  end;
  Say(6, 600);
{$ifdef TEST_ON_ESP}
  while True do vTaskDelay(100);
{$endif}
end.
