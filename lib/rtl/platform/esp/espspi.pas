{ SPDX-License-Identifier: Zlib }
unit espspi;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ ESP32 SPI master: the bus surface a device driver is written against. For
  Pascal and for Nil Python.

      import 'espspi.pas' as spi
      spi.open(12, 11, 13)              # SCK, MOSI, MISO on SPI2
      spi.device(10, 1000000, 0)        # CS=GPIO10, 1 MHz, mode 0
      spi.write(10, [0x9F])             # send
      print(spi.read(10, 3, 0))         # 3 bytes in, clocking out 0x00
      buf = [0, 0, 0]
      spi.write_readinto(10, [0x9F, 0, 0], buf)   # full duplex, in place

  The Python names are MicroPython's machine.SPI ones (write, read,
  readinto, write_readinto; read's third argument is its `write` fill byte),
  and only the names: machine.SPI is one bus with one clock and leaves chip
  select to a Pin, where here a bus carries several DEVICES, each with its
  own CS pin, clock and mode, the way IDF's driver and most boards have it
  (a display and an SD card on one bus). So every transfer names its device
  by its CS pin, the way espi2c names one by its address. A device whose CS
  the program drives itself is added with cs = -1, and that is the
  machine.SPI arrangement.

  ONE BUS PER PROGRAM, as in espi2c: a module-level bus keeps every call a
  plain int in and out.

  IDF's spi_master driver (esp_driver_spi). Its three structs are mirrored
  below and they are safe to mirror on the chips this names: no field is
  compiled in per chip, the enums are 4 bytes, and the one 64-bit field is
  padded explicitly rather than trusted to record alignment. Measured against
  ESP-IDF v6.0.1's headers, 2026-09-25, and the offsets checked by a C
  _Static_assert probe built with the S3 toolchain.

  THE CLOCK SOURCE IS PER CHIP, as in espi2c: SPI_CLK_SRC_DEFAULT is
  SOC_MOD_CLK_APB = 4 on the S3, C3 and S2, and something else on later chips
  (the C6 uses PLL_F80M). The chip is asked at run time and a chip not in the
  table is refused with ESP_ERR_NOT_SUPPORTED.

  DMA is on (SPI_DMA_CH_AUTO), so a transfer may be longer than the 64-byte
  FIFO; the driver copies through a bounce buffer when a caller's buffer is
  not DMA-capable. Transfers are polled (spi_device_polling_transmit): they
  spin rather than sleep, which is what a short sensor transaction wants.

  IDF-only. A project using this unit needs esp_driver_spi in its REQUIRES. }

interface

{$ifdef PXX_NILPY}
uses pylib;
{$endif}

const
  SPI_OK                 = 0;
  SPI_ERR_INVALID_ARG    = $102;   { ESP_ERR_INVALID_ARG }
  SPI_ERR_NOT_OPEN       = $103;   { ESP_ERR_INVALID_STATE }
  SPI_ERR_NOT_FOUND      = $105;   { ESP_ERR_NOT_FOUND: no device on that CS }
  SPI_ERR_NOT_SUPPORTED  = $106;   { ESP_ERR_NOT_SUPPORTED }
  SPI2_HOST              = 1;      { the general-purpose SPI; SPI3_HOST = 2 on the S3/S2 }

{ Pascal surface. Each returns the SDK's esp_err_t; 0 is ESP_OK. }
{ Pass -1 for a pin the bus does not use (no MISO on a display, say). }
function SpiOpen(host, sck, mosi, miso: Integer): Integer;
function SpiClose: Integer;
function SpiIsOpen: Boolean;
{ Add a device: cs = its chip-select GPIO, or -1 when the program drives CS
  itself; mode 0..3 is (CPOL, CPHA). One device per CS pin. }
function SpiAddDevice(cs, hz, mode: Integer): Integer;
{ The clock the driver actually set for that device, in kHz; -1 if none. }
function SpiActualKHz(cs: Integer): Integer;
{ Full duplex: len bytes out of wr while len bytes come into rd. Either may
  be nil: a nil wr clocks out zeros, a nil rd discards what comes in. }
function SpiTransfer(cs: Integer; wr, rd: PByte; len: Integer): Integer;
function SpiWrite(cs: Integer; data: PByte; len: Integer): Integer;
{ Read len bytes while clocking out `fill` on MOSI. }
function SpiRead(cs: Integer; data: PByte; len, fill: Integer): Integer;

{$ifdef PXX_NILPY}
{ ---- the Nil Python surface ----------------------------------------------
  Data goes in and comes out as lists of ints 0..255. read returns an empty
  list when the transfer fails; the others return the esp_err_t. }
function open(sck, mosi, miso: Integer): Integer;
function open_host(host, sck, mosi, miso: Integer): Integer;
function device(cs, baudrate, mode: Integer): Integer;
function close: Integer;
function write(cs: Integer; data: TPyList): Integer;
function read(cs, n, fill: Integer): TPyList;
function readinto(cs: Integer; buf: TPyList; fill: Integer): Integer;
function write_readinto(cs: Integer; wdata, into: TPyList): Integer;
{$endif}

implementation

type
  TSpiBusConfig = record           { spi_bus_config_t }
    iocfg:        array[0 .. 8] of Integer;   { mosi, miso, sclk, wp, hd, data4..7 }
    data_io_default_level: Byte;   { bool }
    pad0, pad1, pad2: Byte;
    max_transfer_sz: Integer;
    flags:        LongWord;
    isr_cpu_id:   Integer;         { esp_intr_cpu_affinity_t }
    intr_flags:   Integer;
  end;
  TSpiDevConfig = record           { spi_device_interface_config_t }
    command_bits, address_bits, dummy_bits, mode: Byte;
    clock_source:     Integer;     { spi_clock_source_t }
    duty_cycle_pos:   Word;
    cs_ena_pretrans:  Word;
    cs_ena_posttrans: Byte;
    pad0, pad1, pad2: Byte;
    clock_speed_hz:   Integer;
    input_delay_ns:   Integer;
    sample_point:     Integer;     { spi_sampling_point_t }
    spics_io_num:     Integer;
    flags:            LongWord;
    queue_size:       Integer;
    pre_cb, post_cb:  Pointer;
  end;
  TSpiTrans = record               { spi_transaction_t }
    flags:     LongWord;
    cmd:       Word;
    pad0:      Word;
    addr_lo, addr_hi: LongWord;    { uint64_t addr, 8-aligned at offset 8 }
    length:    LongWord;           { size_t, in BITS }
    rxlength:  LongWord;
    override_freq_hz: LongWord;
    user:      Pointer;
    tx_buffer: Pointer;
    rx_buffer: Pointer;
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
  SPI_DMA_CH_AUTO = 3;
  SPICOMMON_BUSFLAG_MASTER = 1;
  MAX_TRANSFER = 4096;
  MAX_BUF = 256;                   { the Python surface's per-call limit }
  MAX_CS = 63;

function spi_bus_initialize(host: Integer; cfg: Pointer; dma: Integer): Integer; external;
function spi_bus_free(host: Integer): Integer; external;
function spi_bus_add_device(host: Integer; cfg: Pointer; ret: Pointer): Integer; external;
function spi_bus_remove_device(dev: Pointer): Integer; external;
function spi_device_polling_transmit(dev: Pointer; t: Pointer): Integer; external;
function spi_device_get_actual_freq(dev: Pointer; khz: Pointer): Integer; external;
procedure esp_chip_info(info: Pointer); external;

var
  BusHost: Integer;
  BusOpen: Boolean;
  Devs: array[0 .. MAX_CS + 1] of Pointer;   { slot cs + 1; slot 0 is cs = -1 }
  WBuf, RBuf: array[0 .. MAX_BUF - 1] of Byte;

{ SPI_CLK_SRC_DEFAULT for this chip, or -1 if we do not know it. }
function DefaultClockSource: Integer;
var info: TChipInfo;
begin
  info.model := 0;
  esp_chip_info(@info);
  case info.model of
    CHIP_ESP32S3, CHIP_ESP32C3, CHIP_ESP32S2: DefaultClockSource := 4;   { SOC_MOD_CLK_APB }
  else
    DefaultClockSource := -1;
  end;
end;

function SpiOpen(host, sck, mosi, miso: Integer): Integer;
var cfg: TSpiBusConfig; i, rc: Integer;
begin
  if BusOpen then begin SpiOpen := SPI_ERR_NOT_OPEN; Exit; end;   { already open }
  if DefaultClockSource < 0 then begin SpiOpen := SPI_ERR_NOT_SUPPORTED; Exit; end;
  FillChar(cfg, SizeOf(cfg), 0);
  for i := 0 to 8 do cfg.iocfg[i] := -1;
  cfg.iocfg[0] := mosi;
  cfg.iocfg[1] := miso;
  cfg.iocfg[2] := sck;
  cfg.max_transfer_sz := MAX_TRANSFER;
  cfg.flags := SPICOMMON_BUSFLAG_MASTER;
  rc := spi_bus_initialize(host, @cfg, SPI_DMA_CH_AUTO);
  if rc = 0 then
  begin
    BusOpen := True;
    BusHost := host;
    for i := 0 to MAX_CS + 1 do Devs[i] := nil;
  end;
  SpiOpen := rc;
end;

function SpiClose: Integer;
var i: Integer;
begin
  if not BusOpen then begin SpiClose := SPI_ERR_NOT_OPEN; Exit; end;
  for i := 0 to MAX_CS + 1 do
    if Devs[i] <> nil then
    begin
      spi_bus_remove_device(Devs[i]);
      Devs[i] := nil;
    end;
  SpiClose := spi_bus_free(BusHost);
  BusOpen := False;
end;

function SpiIsOpen: Boolean;
begin
  SpiIsOpen := BusOpen;
end;

function SpiAddDevice(cs, hz, mode: Integer): Integer;
var cfg: TSpiDevConfig; h: Pointer; rc: Integer;
begin
  if not BusOpen then begin SpiAddDevice := SPI_ERR_NOT_OPEN; Exit; end;
  if (cs < -1) or (cs > MAX_CS) or (mode < 0) or (mode > 3) or (hz <= 0) then
  begin SpiAddDevice := SPI_ERR_INVALID_ARG; Exit; end;
  if Devs[cs + 1] <> nil then begin SpiAddDevice := SPI_ERR_NOT_OPEN; Exit; end;
  FillChar(cfg, SizeOf(cfg), 0);
  cfg.mode := mode;
  cfg.clock_source := DefaultClockSource;
  cfg.clock_speed_hz := hz;
  cfg.spics_io_num := cs;
  cfg.queue_size := 1;             { polled transfers: never more than one in flight }
  h := nil;
  rc := spi_bus_add_device(BusHost, @cfg, @h);
  if rc = 0 then Devs[cs + 1] := h;
  SpiAddDevice := rc;
end;

function Dev(cs: Integer; var rc: Integer): Pointer;
begin
  Dev := nil;
  if not BusOpen then begin rc := SPI_ERR_NOT_OPEN; Exit; end;
  if (cs < -1) or (cs > MAX_CS) then begin rc := SPI_ERR_INVALID_ARG; Exit; end;
  if Devs[cs + 1] = nil then begin rc := SPI_ERR_NOT_FOUND; Exit; end;
  rc := 0;
  Dev := Devs[cs + 1];
end;

function SpiActualKHz(cs: Integer): Integer;
var d: Pointer; rc, khz: Integer;
begin
  SpiActualKHz := -1;
  d := Dev(cs, rc);
  if d = nil then Exit;
  khz := 0;
  if spi_device_get_actual_freq(d, @khz) = 0 then SpiActualKHz := khz;
end;

function SpiTransfer(cs: Integer; wr, rd: PByte; len: Integer): Integer;
var d: Pointer; rc: Integer; t: TSpiTrans;
begin
  d := Dev(cs, rc);
  if d = nil then begin SpiTransfer := rc; Exit; end;
  if (len < 0) or (len > MAX_TRANSFER) then begin SpiTransfer := SPI_ERR_INVALID_ARG; Exit; end;
  if len = 0 then begin SpiTransfer := 0; Exit; end;
  FillChar(t, SizeOf(t), 0);
  t.length := len * 8;
  if rd <> nil then t.rxlength := len * 8;
  t.tx_buffer := wr;
  t.rx_buffer := rd;
  SpiTransfer := spi_device_polling_transmit(d, @t);
end;

function SpiWrite(cs: Integer; data: PByte; len: Integer): Integer;
begin
  SpiWrite := SpiTransfer(cs, data, nil, len);
end;

function SpiRead(cs: Integer; data: PByte; len, fill: Integer): Integer;
var i, n, done, rc: Integer;
begin
  if (fill < 0) or (fill > 255) then begin SpiRead := SPI_ERR_INVALID_ARG; Exit; end;
  if fill = 0 then begin SpiRead := SpiTransfer(cs, nil, data, len); Exit; end;
  { A non-zero fill needs a buffer of it; clock it out in WBuf-sized pieces. }
  for i := 0 to MAX_BUF - 1 do WBuf[i] := fill;
  done := 0;
  rc := 0;
  while (done < len) and (rc = 0) do
  begin
    n := len - done;
    if n > MAX_BUF then n := MAX_BUF;
    rc := SpiTransfer(cs, @WBuf[0], data + done, n);
    done := done + n;
  end;
  SpiRead := rc;
end;

{$ifdef PXX_NILPY}
{ ---- the Nil Python surface ---------------------------------------------- }

function open(sck, mosi, miso: Integer): Integer;
begin
  open := SpiOpen(SPI2_HOST, sck, mosi, miso);
end;

function open_host(host, sck, mosi, miso: Integer): Integer;
begin
  open_host := SpiOpen(host, sck, mosi, miso);
end;

function device(cs, baudrate, mode: Integer): Integer;
begin
  device := SpiAddDevice(cs, baudrate, mode);
end;

function close: Integer;
begin
  close := SpiClose;
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

procedure RBufIntoList(buf: TPyList; n: Integer);
var i: Integer; v: Variant;
begin
  for i := 0 to n - 1 do
  begin
    v := Integer(RBuf[i]);
    buf.put(i, v);
  end;
end;

function write(cs: Integer; data: TPyList): Integer;
var n: Integer;
begin
  n := FillWBuf(data);
  if n < 0 then begin write := SPI_ERR_INVALID_ARG; Exit; end;
  write := SpiWrite(cs, @WBuf[0], n);
end;

function read(cs, n, fill: Integer): TPyList;
var i: Integer; v: Variant;
begin
  Result := TPyList.Create;
  if (n < 1) or (n > MAX_BUF) or (SpiRead(cs, @RBuf[0], n, fill) <> 0) then Exit;
  for i := 0 to n - 1 do
  begin
    v := Integer(RBuf[i]);
    Result.append(v);
  end;
end;

{ Fill buf in place, as many bytes as it already holds. }
function readinto(cs: Integer; buf: TPyList; fill: Integer): Integer;
var n, rc: Integer;
begin
  n := buf.count;
  if n > MAX_BUF then begin readinto := SPI_ERR_INVALID_ARG; Exit; end;
  rc := SpiRead(cs, @RBuf[0], n, fill);
  if rc = 0 then RBufIntoList(buf, n);
  readinto := rc;
end;

{ Full duplex: wdata goes out while `into` fills in place. MicroPython requires
  the two to be the same length, and so does this. The list is `into` and
  not `rbuf`: Pascal names are case-insensitive, and a parameter rbuf hides
  the unit's RBuf -- @RBuf[0] then compiled to an address inside the LIST,
  the transfer landed there, and the call returned 0 with the list unchanged
  (measured on the S3, 2026-09-25). }
function write_readinto(cs: Integer; wdata, into: TPyList): Integer;
var n, rc: Integer;
begin
  n := FillWBuf(wdata);
  if (n < 0) or (n <> into.count) then begin write_readinto := SPI_ERR_INVALID_ARG; Exit; end;
  rc := SpiTransfer(cs, @WBuf[0], @RBuf[0], n);
  if rc = 0 then RBufIntoList(into, n);
  write_readinto := rc;
end;

{$endif}

end.
