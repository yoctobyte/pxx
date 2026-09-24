{ SPDX-License-Identifier: Zlib }
unit espuart;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ ESP32 serial ports other than the console: UART1 (and UART2 on the S3).
  For Pascal and for Nil Python; ints and strings, no Python runtime needed.

      import 'espuart.pas' as uart
      uart.open(1, 17, 18, 115200)     # port 1, TX on GPIO17, RX on GPIO18
      uart.write(1, "AT\r\n")
      reply = uart.read(1, 64, 200)    # up to 64 bytes, waiting up to 200 ms
      uart.close(1)

  UART0 IS REFUSED (ESP_ERR_INVALID_ARG). It carries the console -- print,
  WriteLn and the boot log -- and a driver installed over it would take the
  console away from the program that is trying to report something.

  8 data bits, no parity, 1 stop bit, no flow control: what nearly every
  device on the other end of a serial line expects. The driver keeps a 1 KiB
  receive buffer, filled by interrupt, so bytes that arrive between two reads
  are kept (up to that size) rather than lost.

  read() WAITS UP TO timeout_ms FOR THE FIRST BYTES and returns what came, which
  may be fewer than asked for, or '' on a timeout. The wait is in FreeRTOS
  ticks, rounded up; at the IDF default of 100 Hz that is 10 ms steps.

  Strings are bytes: read() returns exactly the bytes that arrived, which for
  a text protocol is the text.

  The config struct is mirrored below. Its clock field is UART_SCLK_DEFAULT,
  which is SOC_MOD_CLK_APB = 4 on the S2, S3 and C3 alike (clk_tree_defs.h,
  ESP-IDF v6.0.1, measured 2026-09-24).

  IDF-only. A project using this unit needs esp_driver_uart in its REQUIRES. }

interface

const
  UART_ERR_INVALID_ARG   = $102;
  UART_ERR_INVALID_STATE = $103;

{ Pascal surface. Open/Close/Loopback return the SDK's esp_err_t; 0 is ESP_OK. }
function UartOpen(port, txPin, rxPin, baud: Integer): Integer;
function UartClose(port: Integer): Integer;
{ Bytes queued for sending, or -1 when the port is not open. }
function UartWrite(port: Integer; buf: Pointer; n: Integer): Integer;
function UartWriteStr(port: Integer; const s: string): Integer;
{ Bytes read into buf (0 on a timeout), or -1 when the port is not open. }
function UartRead(port: Integer; buf: Pointer; n, timeoutMs: Integer): Integer;
function UartReadStr(port, maxLen, timeoutMs: Integer): string;
{ Bytes received and not yet read, or -1 when the port is not open. }
function UartAvailable(port: Integer): Integer;
{ Wait until everything written has left the TX pin. }
function UartFlush(port, timeoutMs: Integer): Integer;
{ Connect the port's TX to its own RX inside the chip: a self-test that needs
  no wire and no pin. }
function UartLoopback(port: Integer; enable: Boolean): Integer;

{$ifdef PXX_NILPY}
{ Under PXX_NILPY only: to a Pascal program, `write` and `read` here would
  shadow the built-in Write and Read. }
{ ---- the Nil Python surface ---------------------------------------------- }
function open(port, tx, rx, baud: Integer): Integer;
function close(port: Integer): Integer;
function write(port: Integer; s: string): Integer;
function read(port, max_len, timeout_ms: Integer): string;
function available(port: Integer): Integer;
function flush(port, timeout_ms: Integer): Integer;
function loopback(port, enable: Integer): Integer;

{$endif}

implementation

type
  TUartConfig = record          { uart_config_t, ESP-IDF v6.0.1: 32 bytes }
    baud_rate:  Integer;
    data_bits:  Integer;        { UART_DATA_8_BITS = 3 }
    parity:     Integer;        { UART_PARITY_DISABLE = 0 }
    stop_bits:  Integer;        { UART_STOP_BITS_1 = 1 }
    flow_ctrl:  Integer;        { UART_HW_FLOWCTRL_DISABLE = 0 }
    rx_flow_ctrl_thresh: Byte;
    pad0, pad1, pad2: Byte;
    source_clk: Integer;        { UART_SCLK_DEFAULT = SOC_MOD_CLK_APB = 4 }
    flags:      LongWord;
  end;

const
  UART_PORTS = 3;               { 0 (refused), 1, 2 -- the S3 has UART2 }
  RX_BUF = 1024;
  TICK_MS = 10;                 { FreeRTOS tick at the IDF default of 100 Hz }

function uart_driver_install(port, rxBuf, txBuf, queueSize: Integer; queue: Pointer; intrFlags: Integer): Integer; cdecl; external;
function uart_driver_delete(port: Integer): Integer; cdecl; external;
function uart_param_config(port: Integer; cfg: Pointer): Integer; cdecl; external;
function _uart_set_pin6(port, tx, rx, rts, cts, dtr, dsr: Integer): Integer; cdecl; external;
function uart_write_bytes(port: Integer; src: Pointer; size: PtrUInt): Integer; cdecl; external;
function uart_read_bytes(port: Integer; buf: Pointer; len: LongWord; ticks: LongWord): Integer; cdecl; external;
function uart_get_buffered_data_len(port: Integer; size: Pointer): Integer; cdecl; external;
function uart_wait_tx_done(port: Integer; ticks: LongWord): Integer; cdecl; external;
function uart_set_loop_back(port: Integer; enable: Boolean): Integer; cdecl; external;

var
  IsOpen: array[0 .. UART_PORTS - 1] of Boolean;

function Usable(port: Integer): Boolean;
begin
  Usable := (port >= 1) and (port < UART_PORTS) and IsOpen[port];
end;

function Ticks(ms: Integer): LongWord;
begin
  if ms <= 0 then Ticks := 0
  else Ticks := LongWord((ms + TICK_MS - 1) div TICK_MS);
end;

function UartOpen(port, txPin, rxPin, baud: Integer): Integer;
var cfg: TUartConfig; rc: Integer;
begin
  if (port < 1) or (port >= UART_PORTS) or (baud <= 0) then
  begin
    UartOpen := UART_ERR_INVALID_ARG;
    Exit;
  end;
  if IsOpen[port] then begin UartOpen := UART_ERR_INVALID_STATE; Exit; end;
  FillChar(cfg, SizeOf(cfg), 0);
  cfg.baud_rate := baud;
  cfg.data_bits := 3;
  cfg.parity := 0;
  cfg.stop_bits := 1;
  cfg.flow_ctrl := 0;
  cfg.source_clk := 4;
  rc := uart_driver_install(port, RX_BUF, 0, 0, nil, 0);
  if rc <> 0 then begin UartOpen := rc; Exit; end;
  rc := uart_param_config(port, @cfg);
  if rc = 0 then rc := _uart_set_pin6(port, txPin, rxPin, -1, -1, -1, -1);
  if rc <> 0 then
  begin
    uart_driver_delete(port);
    UartOpen := rc;
    Exit;
  end;
  IsOpen[port] := True;
  UartOpen := 0;
end;

function UartClose(port: Integer): Integer;
begin
  if not Usable(port) then begin UartClose := UART_ERR_INVALID_STATE; Exit; end;
  IsOpen[port] := False;
  UartClose := uart_driver_delete(port);
end;

function UartWrite(port: Integer; buf: Pointer; n: Integer): Integer;
begin
  if not Usable(port) then begin UartWrite := -1; Exit; end;
  if n <= 0 then begin UartWrite := 0; Exit; end;
  UartWrite := uart_write_bytes(port, buf, PtrUInt(n));
end;

function UartWriteStr(port: Integer; const s: string): Integer;
begin
  if Length(s) = 0 then
  begin
    if Usable(port) then UartWriteStr := 0 else UartWriteStr := -1;
    Exit;
  end;
  UartWriteStr := UartWrite(port, @s[1], Length(s));
end;

function UartRead(port: Integer; buf: Pointer; n, timeoutMs: Integer): Integer;
begin
  if not Usable(port) then begin UartRead := -1; Exit; end;
  if n <= 0 then begin UartRead := 0; Exit; end;
  UartRead := uart_read_bytes(port, buf, LongWord(n), Ticks(timeoutMs));
end;

function UartReadStr(port, maxLen, timeoutMs: Integer): string;
var s: string; got: Integer;
begin
  UartReadStr := '';
  if maxLen <= 0 then Exit;
  SetLength(s, maxLen);
  got := UartRead(port, @s[1], maxLen, timeoutMs);
  if got <= 0 then Exit;
  SetLength(s, got);
  UartReadStr := s;
end;

function UartAvailable(port: Integer): Integer;
var n: PtrUInt;
begin
  if not Usable(port) then begin UartAvailable := -1; Exit; end;
  n := 0;
  if uart_get_buffered_data_len(port, @n) <> 0 then UartAvailable := -1
  else UartAvailable := Integer(n);
end;

function UartFlush(port, timeoutMs: Integer): Integer;
begin
  if not Usable(port) then begin UartFlush := UART_ERR_INVALID_STATE; Exit; end;
  UartFlush := uart_wait_tx_done(port, Ticks(timeoutMs));
end;

function UartLoopback(port: Integer; enable: Boolean): Integer;
begin
  if not Usable(port) then begin UartLoopback := UART_ERR_INVALID_STATE; Exit; end;
  UartLoopback := uart_set_loop_back(port, enable);
end;

{$ifdef PXX_NILPY}
{ ---- the Nil Python surface ---------------------------------------------- }

function open(port, tx, rx, baud: Integer): Integer;
begin
  open := UartOpen(port, tx, rx, baud);
end;

function close(port: Integer): Integer;
begin
  close := UartClose(port);
end;

function write(port: Integer; s: string): Integer;
begin
  write := UartWriteStr(port, s);
end;

function read(port, max_len, timeout_ms: Integer): string;
begin
  read := UartReadStr(port, max_len, timeout_ms);
end;

function available(port: Integer): Integer;
begin
  available := UartAvailable(port);
end;

function flush(port, timeout_ms: Integer): Integer;
begin
  flush := UartFlush(port, timeout_ms);
end;

function loopback(port, enable: Integer): Integer;
begin
  loopback := UartLoopback(port, enable <> 0);
end;

{$endif}

end.
