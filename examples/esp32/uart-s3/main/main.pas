{ SPDX-License-Identifier: 0BSD }
program EspUartCheck;
{ UART1 TESTED ON ONE BOARD WITH NOTHING WIRED.

  lib/rtl/platform/esp/espuart.pas drives UART1. Two paths bring what it sends
  back to its own receiver without a wire:
    loopback   the UART's internal TX->RX connection: the driver, the FIFO and
               the baud generator, but no pin
    one pad    TX and RX both routed to GPIO17. The pad's output drives its own
               input, so the bytes leave through the GPIO matrix and come back
               through it: the path a real wire would use
  Rows:
    console refused  UART0 carries the console; open(0) answers INVALID_ARG
    loopback echo    "hello uart1" comes back byte for byte
    available        after writing 5 bytes and waiting, 5 are buffered
    timeout          reading an idle line returns 0 bytes after ~200 ms
                     (asked 200; 180..260 passes)
    fast echo        the same at 1,000,000 baud
    pad echo         the loopback OFF, one pad: the text comes back through it
    pad control      the same pad path, TX moved to another pin: NOTHING comes
                     back -- the control that the echo above came through GPIO17
    closed           writing to a closed port answers -1
  Each prints PASS or FAIL; the last line is UART-CHECK-DONE with the counts. }

uses espuart, espsys;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;

const
  PAD = 17;
  OTHER = 18;
  MSG = 'hello uart1';

var
  Passed, Failed: Integer;

procedure Row(name: string; ok: Boolean; detail: Integer);
begin
  esp_rom_printf(name, 0);
  if ok then begin esp_rom_printf(' PASS (%d)'#10, detail); Passed := Passed + 1; end
  else begin esp_rom_printf(' FAIL (%d)'#10, detail); Failed := Failed + 1; end;
end;

{ Write s, then read back up to 64 bytes with a 200 ms wait. }
function Echo(const s: string): string;
begin
  UartWriteStr(1, s);
  UartFlush(1, 100);
  Echo := UartReadStr(1, 64, 200);
end;

var rc, n: Integer; t0: Int64; s: string;
begin
  esp_rom_printf('UART-CHECK on UART1, pad GPIO%d'#10, PAD);

  Row('console refused', UartOpen(0, PAD, PAD, 115200) = UART_ERR_INVALID_ARG, 0);

  rc := UartOpen(1, PAD, OTHER, 115200);
  Row('open', rc = 0, rc);
  Row('loopback on', UartLoopback(1, True) = 0, 0);
  s := Echo(MSG);
  Row('loopback echo', s = MSG, Length(s));

  UartWriteStr(1, '12345');
  UartFlush(1, 100);
  vTaskDelay(2);
  n := UartAvailable(1);
  Row('available', n = 5, n);
  s := UartReadStr(1, 64, 0);
  Row('drain', s = '12345', Length(s));

  t0 := EspUptimeMs;
  s := UartReadStr(1, 8, 200);
  n := Integer(EspUptimeMs - t0);
  Row('timeout empty', s = '', Length(s));
  Row('timeout ms', (n >= 180) and (n <= 260), n);
  UartClose(1);

  rc := UartOpen(1, PAD, OTHER, 1000000);
  UartLoopback(1, True);
  s := Echo(MSG + ' at 1M');
  Row('fast echo', s = MSG + ' at 1M', Length(s));
  UartClose(1);

  rc := UartOpen(1, PAD, PAD, 115200);
  Row('pad open', rc = 0, rc);
  s := Echo(MSG);
  Row('pad echo', s = MSG, Length(s));
  UartClose(1);

  rc := UartOpen(1, OTHER, PAD, 115200);
  s := Echo(MSG);
  Row('pad control', (rc = 0) and (s = ''), Length(s));
  UartClose(1);

  Row('closed', UartWriteStr(1, MSG) = -1, 0);

  esp_rom_printf('UART-CHECK-DONE passed=%d', Passed);
  esp_rom_printf(' failed=%d'#10, Failed);
  while True do vTaskDelay(1000);
end.
