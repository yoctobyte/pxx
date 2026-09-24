{ SPDX-License-Identifier: 0BSD }
program EspI2cLoopback;
{ THE I2C BUS, TESTED ON ONE BOARD WITH TWO JUMPER WIRES AND NO DEVICE.

  The ESP32-S3 has two I2C controllers. This program makes controller 0 the
  master (through lib/rtl/platform/esp/espi2c.pas, the unit under test) on
  GPIO 17 (SDA) / 18 (SCL), and controller 1 a slave at address $28 on GPIO
  15 / 16. Wire 17 to 15 and 18 to 16 and the master talks to the slave over
  a real open-drain bus, with the internal pull-ups, exactly as it would talk
  to a sensor.

  WHY TWO PAIRS AND WIRES, AND NOT ONE PAIR SHARED INSIDE THE CHIP: a pad's
  OUTPUT takes exactly one peripheral signal through the GPIO matrix, so the
  second controller to claim a pad takes it from the first. Measured
  2026-09-24: with both on 17/18, IDF warns "GPIO 17 is not usable, maybe
  conflict with others" and every probe times out. An I2C bus is a wired-AND
  of both sides' outputs, and the matrix cannot build that on one pad.

  The slave is IDF's own driver, declared here and not in espi2c: it is the
  test fixture, not the surface being tested. Its receive callback runs in
  interrupt context and only copies the bytes into a static buffer.

  WITHOUT THE WIRES the program says so and runs only what an empty bus can
  answer: open, a scan that finds nobody, a NACK, and close.

  Rows, and what each can fail on:
    scan      exactly [$28] ACKs. A floating or shorted bus gives none or all.
    nack      $29 answers ESP_ERR_NOT_FOUND. A probe that always says yes fails.
    write     the slave receives the three bytes the master sent, in order.
    read      the master reads back the bytes the slave queued.
    gone      with the slave deleted, the scan is empty. This is the control
              that the ACKs above came from the slave and nothing else.
  Each prints PASS or FAIL; the last line is I2C-LOOPBACK-DONE with the count. }

uses espi2c;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;

type
  TSlaveConfig = record            { i2c_slave_config_t, ESP-IDF v6.0.1 }
    i2c_port, sda_io_num, scl_io_num, clk_source: Integer;
    send_buf_depth, receive_buf_depth: LongWord;
    slave_addr: Word;
    pad0: Word;
    addr_bit_len: Integer;
    intr_priority: Integer;
    flags: LongWord;               { bit 0 allow_pd, bit 1 enable_internal_pullup }
  end;
  TSlaveCbs = record               { i2c_slave_event_callbacks_t }
    on_request: Pointer;
    on_receive: Pointer;
  end;
  TRxEvent = record                { i2c_slave_rx_done_event_data_t }
    buffer: PByte;
    length: LongWord;
  end;
  PRxEvent = ^TRxEvent;

function i2c_new_slave_device(cfg: Pointer; ret: Pointer): Integer; external;
function i2c_del_slave_device(h: Pointer): Integer; external;
function i2c_slave_register_event_callbacks(h: Pointer; cbs: Pointer; user: Pointer): Integer; external;
function i2c_slave_write(h: Pointer; data: PByte; len: LongWord; written: Pointer; timeoutMs: Integer): Integer; external;

const
  SDA = 17;                        { master }
  SCL = 18;
  SLAVE_SDA = 15;                  { slave; jumper 17-15 and 18-16 }
  SLAVE_SCL = 16;
  SLAVE_ADDR = $28;
  S3_CLK_XTAL = 11;                { I2C_CLK_SRC_DEFAULT on the S3; see espi2c }

var
  Slave: Pointer;
  RxBuf: array[0 .. 31] of Byte;
  RxLen: Integer;
  Passed, Failed: Integer;

{ INTERRUPT CONTEXT: copy and count, nothing else. }
function OnReceive(h: Pointer; ev: PRxEvent; user: Pointer): Boolean;
var i, n: Integer;
begin
  n := ev^.length;
  if n > 32 then n := 32;
  for i := 0 to n - 1 do RxBuf[i] := ev^.buffer[i];
  RxLen := n;
  Result := False;
end;

procedure Row(name: string; ok: Boolean; detail: Integer);
begin
  esp_rom_printf(name, 0);
  if ok then
  begin
    esp_rom_printf(' PASS (%d)'#10, detail);
    Passed := Passed + 1;
  end
  else
  begin
    esp_rom_printf(' FAIL (%d)'#10, detail);
    Failed := Failed + 1;
  end;
end;

function StartSlave: Integer;
var cfg: TSlaveConfig; cbs: TSlaveCbs; rc: Integer;
begin
  FillChar(cfg, SizeOf(cfg), 0);
  cfg.i2c_port := 1;
  cfg.sda_io_num := SLAVE_SDA;
  cfg.scl_io_num := SLAVE_SCL;
  cfg.clk_source := S3_CLK_XTAL;
  cfg.send_buf_depth := 64;
  cfg.receive_buf_depth := 64;
  cfg.slave_addr := SLAVE_ADDR;
  cfg.addr_bit_len := 0;
  cfg.flags := 2;                  { internal pull-up }
  Slave := nil;
  rc := i2c_new_slave_device(@cfg, @Slave);
  if rc <> 0 then begin StartSlave := rc; Exit; end;
  cbs.on_request := nil;
  cbs.on_receive := @OnReceive;
  StartSlave := i2c_slave_register_event_callbacks(Slave, @cbs, nil);
end;

{ How many addresses 0x08..0x77 ACK, and the first one that did. }
function ScanCount(var first: Integer): Integer;
var a, n: Integer;
begin
  n := 0;
  first := -1;
  for a := $08 to $77 do
    if I2cProbe(a) = 0 then
    begin
      if first < 0 then first := a;
      n := n + 1;
    end;
  ScanCount := n;
end;

var
  rc, n, first, written: Integer;
  wr: array[0 .. 2] of Byte;
  rd: array[0 .. 2] of Byte;
  reply: array[0 .. 2] of Byte;
begin
  esp_rom_printf('I2C-LOOPBACK master I2C0 on SDA=%d', SDA);
  esp_rom_printf(' SCL=%d, slave I2C1 at $28 on 15/16'#10, SCL);
  rc := I2cOpen(0, SDA, SCL, 100000);
  Row('open', rc = 0, rc);
  rc := StartSlave;
  Row('slave', rc = 0, rc);
  vTaskDelay(2);

  n := ScanCount(first);
  if n = 0 then
  begin
    { Nobody answered, not even the slave: the jumpers are not fitted. }
    esp_rom_printf('I2C-LOOPBACK NO-JUMPERS: wire GPIO17-GPIO15 and GPIO18-GPIO16 for the full test %d'#10, 0);
    Row('empty scan', n = 0, n);
    rc := I2cProbe(SLAVE_ADDR + 1);
    Row('nack', rc = I2C_ERR_NOT_FOUND, rc);
    i2c_del_slave_device(Slave);
  end
  else
  begin
    Row('scan count', n = 1, n);
    Row('scan addr', first = SLAVE_ADDR, first);
    rc := I2cProbe(SLAVE_ADDR + 1);
    Row('nack', rc = I2C_ERR_NOT_FOUND, rc);

    wr[0] := $A5; wr[1] := $5A; wr[2] := $01;
    RxLen := 0;
    rc := I2cWrite(SLAVE_ADDR, @wr[0], 3);
    vTaskDelay(2);
    Row('write rc', rc = 0, rc);
    Row('write len', RxLen = 3, RxLen);
    Row('write bytes', (RxBuf[0] = $A5) and (RxBuf[1] = $5A) and (RxBuf[2] = $01),
        RxBuf[0] * 65536 + RxBuf[1] * 256 + RxBuf[2]);

    reply[0] := Ord('O'); reply[1] := Ord('K'); reply[2] := Ord('!');
    written := 0;
    rc := i2c_slave_write(Slave, @reply[0], 3, @written, 100);
    Row('slave queue', rc = 0, written);
    rd[0] := 0; rd[1] := 0; rd[2] := 0;
    rc := I2cRead(SLAVE_ADDR, @rd[0], 3);
    Row('read rc', rc = 0, rc);
    Row('read bytes', (rd[0] = Ord('O')) and (rd[1] = Ord('K')) and (rd[2] = Ord('!')),
        rd[0] * 65536 + rd[1] * 256 + rd[2]);

    i2c_del_slave_device(Slave);
    vTaskDelay(2);
    n := ScanCount(first);
    Row('gone', n = 0, n);
  end;

  rc := I2cClose;
  Row('close', rc = 0, rc);
  esp_rom_printf('I2C-LOOPBACK-DONE passed=%d', Passed);
  esp_rom_printf(' failed=%d'#10, Failed);
  while True do vTaskDelay(1000);
end.
