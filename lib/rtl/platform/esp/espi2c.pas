{ SPDX-License-Identifier: Zlib }
unit espi2c;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ ESP32 I2C master: the bus surface a device driver is written against. For
  Pascal and for Nil Python.

      import 'espi2c.pas' as i2c
      i2c.open(8, 9, 100000)          # SDA, SCL, clock in Hz
      print(i2c.scan())               # [0x3c, 0x76] -- who answers
      i2c.write(0x76, [0xF4, 0x27])   # register 0xF4 := 0x27
      print(i2c.write_read(0x76, [0xD0], 1))   # read register 0xD0

  ONE BUS PER PROGRAM, and that is a choice, not a limit of the chip: almost
  every board has one I2C bus with several devices on it, and a module-level
  bus keeps every call a plain int in and out. Devices are added to the bus on
  first use, one per 7-bit address, all at the clock given to open().

  IDF's new driver (esp_driver_i2c, i2c_master.h), not the legacy i2c.h one.
  Its two config structs are mirrored below, and they are safe to mirror on
  the chips this names: no field is compiled in per chip, the one union holds
  two 4-byte enums, and the flag bit-fields fit one uint32. Measured against
  ESP-IDF v6.0.1's headers, 2026-09-24.

  THE CLOCK SOURCE IS PER CHIP, AND GUESSING IT WRONG IS SILENT. The driver
  wants I2C_CLK_SRC_DEFAULT, a soc_module_clk_t whose NUMBER differs by chip
  (soc/<chip>/include/soc/clk_tree_defs.h): 11 on the S3 (XTAL), 10 on the C3
  (XTAL), 4 on the S2 (APB). One build serves several chips per ISA, so the
  compiler cannot pick it; the chip is asked at run time (esp_chip_info, whose
  model numbers Espressif keeps fixed), and a chip not in the table is refused
  with ESP_ERR_NOT_SUPPORTED rather than handed a clock that may not exist.
  Measured on the S3 only; C3 and S2 are from the headers.

  IDF-only. A project using this unit needs esp_driver_i2c in its REQUIRES. }

interface

{ The Python half needs pylib (TPyList), which a Pascal program should not pay
  for, so it is compiled only into a Nil Python program. }
{$ifdef PXX_NILPY}
uses pylib;
{$endif}

const
  I2C_OK                 = 0;
  I2C_ERR_NOT_OPEN       = $103;   { ESP_ERR_INVALID_STATE }
  I2C_ERR_NOT_SUPPORTED  = $106;   { ESP_ERR_NOT_SUPPORTED }
  I2C_ERR_NOT_FOUND      = $105;   { ESP_ERR_NOT_FOUND: nobody ACKed the address }
  I2C_TIMEOUT_MS         = 100;

{ Pascal surface. Each returns the SDK's esp_err_t; 0 is ESP_OK. }
{ port = I2C controller number (0 or 1 on the S3), or -1 to let IDF choose. }
function I2cOpen(port, sda, scl, hz: Integer): Integer;
function I2cClose: Integer;
function I2cIsOpen: Boolean;
{ 0 when a device ACKs addr; I2C_ERR_NOT_FOUND when nobody does. }
function I2cProbe(addr: Integer): Integer;
function I2cWrite(addr: Integer; data: PByte; len: Integer): Integer;
function I2cRead(addr: Integer; data: PByte; len: Integer): Integer;
{ Write then read with a repeated START in between: the usual register read. }
function I2cWriteRead(addr: Integer; wr: PByte; wlen: Integer;
  rd: PByte; rlen: Integer): Integer;

{$ifdef PXX_NILPY}
{ ---- the Nil Python surface ----------------------------------------------
  Data goes in and comes out as lists of ints 0..255. A failed transfer
  returns an empty list from read/write_read; write returns the esp_err_t. }
function open(sda, scl, hz: Integer): Integer;
function open_port(port, sda, scl, hz: Integer): Integer;
function close: Integer;
function probe(addr: Integer): Integer;
function scan: TPyList;
function write(addr: Integer; data: TPyList): Integer;
function read(addr, n: Integer): TPyList;
function write_read(addr: Integer; data: TPyList; n: Integer): TPyList;
{$endif}

implementation

type
  TI2cBusConfig = record           { i2c_master_bus_config_t }
    i2c_port:          Integer;
    sda_io_num:        Integer;
    scl_io_num:        Integer;
    clk_source:        Integer;    { union with lp_source_clk; both 4-byte enums }
    glitch_ignore_cnt: Byte;
    pad0, pad1, pad2:  Byte;
    intr_priority:     Integer;
    trans_queue_depth: LongWord;   { size_t }
    flags:             LongWord;   { bit 0 enable_internal_pullup, bit 1 allow_pd }
  end;
  TI2cDevConfig = record           { i2c_device_config_t }
    dev_addr_length:   Integer;    { I2C_ADDR_BIT_LEN_7 = 0 }
    device_address:    Word;
    pad0:              Word;
    scl_speed_hz:      LongWord;
    scl_wait_us:       LongWord;
    flags:             LongWord;   { bit 0 disable_ack_check }
  end;
  TChipInfo = record               { esp_chip_info_t }
    model:    Integer;
    features: LongWord;
    revision: Word;
    cores:    Byte;
    pad:      Byte;
  end;

const
  CHIP_ESP32S2 = 2;
  CHIP_ESP32C3 = 5;
  CHIP_ESP32S3 = 9;
  ESP_ERR_INVALID_ARG = $102;
  MAX_BUF = 256;

function i2c_new_master_bus(cfg: Pointer; ret: Pointer): Integer; external;
function i2c_del_master_bus(bus: Pointer): Integer; external;
function i2c_master_bus_add_device(bus: Pointer; cfg: Pointer; ret: Pointer): Integer; external;
function i2c_master_bus_rm_device(dev: Pointer): Integer; external;
function i2c_master_probe(bus: Pointer; address: Word; timeoutMs: Integer): Integer; external;
function i2c_master_transmit(dev: Pointer; buf: PByte; len: LongWord; timeoutMs: Integer): Integer; external;
function i2c_master_receive(dev: Pointer; buf: PByte; len: LongWord; timeoutMs: Integer): Integer; external;
function i2c_master_transmit_receive(dev: Pointer; wr: PByte; wlen: LongWord;
  rd: PByte; rlen: LongWord; timeoutMs: Integer): Integer; external;
procedure esp_chip_info(info: Pointer); external;

var
  Bus: Pointer;
  BusHz: Integer;
  Devs: array[0 .. 127] of Pointer;
  WBuf, RBuf: array[0 .. MAX_BUF - 1] of Byte;

{ I2C_CLK_SRC_DEFAULT for this chip, or -1 if we do not know it. See the
  header: the number is per chip and the build cannot tell which chip. }
function DefaultClockSource: Integer;
var info: TChipInfo;
begin
  info.model := 0;
  esp_chip_info(@info);
  case info.model of
    CHIP_ESP32S3: DefaultClockSource := 11;
    CHIP_ESP32C3: DefaultClockSource := 10;
    CHIP_ESP32S2: DefaultClockSource := 4;
  else
    DefaultClockSource := -1;
  end;
end;

function I2cOpen(port, sda, scl, hz: Integer): Integer;
var cfg: TI2cBusConfig; clk, i: Integer; h: Pointer;
begin
  if Bus <> nil then begin I2cOpen := I2C_ERR_NOT_OPEN; Exit; end;   { already open }
  clk := DefaultClockSource;
  if clk < 0 then begin I2cOpen := I2C_ERR_NOT_SUPPORTED; Exit; end;
  FillChar(cfg, SizeOf(cfg), 0);
  cfg.i2c_port := port;
  cfg.sda_io_num := sda;
  cfg.scl_io_num := scl;
  cfg.clk_source := clk;
  cfg.glitch_ignore_cnt := 7;      { the driver documentation's typical value }
  cfg.flags := 1;                  { internal pull-ups; fine for short wires at 100 kHz }
  h := nil;
  I2cOpen := i2c_new_master_bus(@cfg, @h);
  if h <> nil then
  begin
    Bus := h;
    BusHz := hz;
    for i := 0 to 127 do Devs[i] := nil;
  end;
end;

function I2cClose: Integer;
var i: Integer;
begin
  if Bus = nil then begin I2cClose := I2C_ERR_NOT_OPEN; Exit; end;
  for i := 0 to 127 do
    if Devs[i] <> nil then
    begin
      i2c_master_bus_rm_device(Devs[i]);
      Devs[i] := nil;
    end;
  I2cClose := i2c_del_master_bus(Bus);
  Bus := nil;
end;

function I2cIsOpen: Boolean;
begin
  I2cIsOpen := Bus <> nil;
end;

{ The device handle for addr, adding it to the bus on first use. }
function Dev(addr: Integer; var rc: Integer): Pointer;
var cfg: TI2cDevConfig; h: Pointer;
begin
  Dev := nil;
  if Bus = nil then begin rc := I2C_ERR_NOT_OPEN; Exit; end;
  if (addr < 0) or (addr > 127) then begin rc := ESP_ERR_INVALID_ARG; Exit; end;
  if Devs[addr] = nil then
  begin
    FillChar(cfg, SizeOf(cfg), 0);
    cfg.dev_addr_length := 0;      { I2C_ADDR_BIT_LEN_7 }
    cfg.device_address := addr;
    cfg.scl_speed_hz := BusHz;
    h := nil;
    rc := i2c_master_bus_add_device(Bus, @cfg, @h);
    if rc <> 0 then Exit;
    Devs[addr] := h;
  end;
  rc := 0;
  Dev := Devs[addr];
end;

function I2cProbe(addr: Integer): Integer;
begin
  if Bus = nil then begin I2cProbe := I2C_ERR_NOT_OPEN; Exit; end;
  I2cProbe := i2c_master_probe(Bus, addr, I2C_TIMEOUT_MS);
end;

function I2cWrite(addr: Integer; data: PByte; len: Integer): Integer;
var d: Pointer; rc: Integer;
begin
  d := Dev(addr, rc);
  if d = nil then begin I2cWrite := rc; Exit; end;
  I2cWrite := i2c_master_transmit(d, data, len, I2C_TIMEOUT_MS);
end;

function I2cRead(addr: Integer; data: PByte; len: Integer): Integer;
var d: Pointer; rc: Integer;
begin
  d := Dev(addr, rc);
  if d = nil then begin I2cRead := rc; Exit; end;
  I2cRead := i2c_master_receive(d, data, len, I2C_TIMEOUT_MS);
end;

function I2cWriteRead(addr: Integer; wr: PByte; wlen: Integer;
  rd: PByte; rlen: Integer): Integer;
var d: Pointer; rc: Integer;
begin
  d := Dev(addr, rc);
  if d = nil then begin I2cWriteRead := rc; Exit; end;
  I2cWriteRead := i2c_master_transmit_receive(d, wr, wlen, rd, rlen, I2C_TIMEOUT_MS);
end;

{$ifdef PXX_NILPY}
{ ---- the Nil Python surface ---------------------------------------------- }

function open(sda, scl, hz: Integer): Integer;
begin
  open := I2cOpen(-1, sda, scl, hz);
end;

function open_port(port, sda, scl, hz: Integer): Integer;
begin
  open_port := I2cOpen(port, sda, scl, hz);
end;

function close: Integer;
begin
  close := I2cClose;
end;

function probe(addr: Integer): Integer;
begin
  probe := I2cProbe(addr);
end;

{ The addresses 0x08..0x77 that ACK: the 7-bit range minus the reserved ends. }
function scan: TPyList;
var a: Integer; v: Variant;
begin
  Result := TPyList.Create;
  if Bus = nil then Exit;
  for a := $08 to $77 do
    if I2cProbe(a) = 0 then
    begin
      v := a;
      Result.append(v);
    end;
end;

{ Copy a list of ints into WBuf; -1 when it does not fit or holds a non-byte. }
function FillWBuf(data: TPyList): Integer;
var i, n, b: Integer;
begin
  n := data.count;
  if n > MAX_BUF then begin FillWBuf := -1; Exit; end;
  for i := 0 to n - 1 do
  begin
    b := data.at(i);
    if (b < 0) or (b > 255) then begin FillWBuf := -1; Exit; end;
    WBuf[i] := b;
  end;
  FillWBuf := n;
end;

function RBufToList(n: Integer): TPyList;
var i: Integer; v: Variant;
begin
  Result := TPyList.Create;
  for i := 0 to n - 1 do
  begin
    v := Integer(RBuf[i]);
    Result.append(v);
  end;
end;

function write(addr: Integer; data: TPyList): Integer;
var n: Integer;
begin
  n := FillWBuf(data);
  if n < 0 then begin write := ESP_ERR_INVALID_ARG; Exit; end;
  write := I2cWrite(addr, @WBuf[0], n);
end;

function read(addr, n: Integer): TPyList;
begin
  if (n < 1) or (n > MAX_BUF) or (I2cRead(addr, @RBuf[0], n) <> 0) then
    Result := TPyList.Create
  else
    Result := RBufToList(n);
end;

function write_read(addr: Integer; data: TPyList; n: Integer): TPyList;
var w: Integer;
begin
  w := FillWBuf(data);
  if (w < 0) or (n < 1) or (n > MAX_BUF)
     or (I2cWriteRead(addr, @WBuf[0], w, @RBuf[0], n) <> 0) then
    Result := TPyList.Create
  else
    Result := RBufToList(n);
end;

{$endif}

end.
