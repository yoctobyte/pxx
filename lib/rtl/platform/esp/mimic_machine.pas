{ SPDX-License-Identifier: Zlib }
unit mimic_machine;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ MicroPython's `machine` module -- Pin, I2C, SoftI2C, SPI -- for a NilPy
  program on an ESP32, so a MicroPython device driver compiles UNCHANGED:

      from machine import Pin, I2C
      import ssd1306                         # micropython-lib, as published
      i2c = I2C(0, scl=Pin(9), sda=Pin(8), freq=400000)
      oled = ssd1306.SSD1306_I2C(128, 64, i2c)

  That is the whole reason for the names (the owner's: driver reuse), so the
  NAMES, argument ORDER and keyword spellings are MicroPython's ESP32 port's
  (ports/esp32/machine_pin.c, machine_i2c.c, machine_hw_spi.c), and so is the
  failure a driver sees with no device attached: a NACK is
  OSError('[Errno 19] ENODEV') and a bus timeout OSError('[Errno 110]
  ETIMEDOUT'), which is MicroPython's own str() for those -- the ESP32 port
  maps ESP_FAIL to ENODEV and ESP_ERR_TIMEOUT to ETIMEDOUT, everything else
  to its own number. A driver's init therefore FAILS, it does not hang.

  Over espgpio/espi2c/espspi, which own the IDF structs. What differs:
    * ONE I2C bus and ONE SPI bus per program, as those units have it -- a
      second I2C(...) re-opens the same bus on the new pins. Nearly every board
      has one of each; a program with two is refused by the underlying open.
    * SoftI2C is the hardware controller under MicroPython's name (the same
      bytes on the wire; MicroPython's bit-banged one exists for pins the
      hardware cannot route, which on an ESP32's GPIO matrix is none).
    * SPI chip select is the program's Pin, exactly as MicroPython leaves it.
    * bits/firstbit are accepted and must be 8 / MSB: the only values the
      published drivers use.

  Only for an ESP build: this file lives in lib/rtl/platform/esp, on the unit
  path of an --platform=esp compile and nothing else. A project needs
  esp_driver_gpio, esp_driver_i2c, esp_driver_spi and esp_driver_rmt in its
  REQUIRES (rmt for bitstream).

  The microsecond pin protocols MicroPython writes in C are here too:
  time_pulse_us and dht_readinto are espmpyport's translation of MicroPython's
  own (MIT, see that unit), and bitstream drives the RMT peripheral as
  MicroPython's ESP32 port does. }

interface

uses pylib, sysutils, espgpio, espi2c, espspi, mimic_time, espmpyport;

type
  Pin = class
  public
    { MicroPython ESP32's numbers (machine_pin.c), so a program that stores
      or prints one sees what it would there. }
    const &IN = 1;
    const OUT = 3;
    const OPEN_DRAIN = 7;
    const PULL_UP = 2;
    const PULL_DOWN = 1;
    const IRQ_RISING = 1;
    const IRQ_FALLING = 2;
    var id: Integer;
    constructor Create(id: Integer; mode: Integer = -1; pull: Integer = -1;
                       value: Integer = -1);
    procedure init(mode: Integer = -1; pull: Integer = -1; value: Integer = -1);
    function value: Integer; overload;
    procedure value(v: Integer); overload;
    function __call__: Integer; overload;
    procedure __call__(v: Integer); overload;
    procedure &on;
    procedure off;
  end;

  I2C = class
  public
    constructor Create(id: Integer = 0; scl: Pin = nil; sda: Pin = nil;
                       freq: Integer = 400000; timeout: Integer = 50000);
    procedure init(scl: Pin = nil; sda: Pin = nil; freq: Integer = 400000;
                   timeout: Integer = 50000);
    function scan: TPyList;
    function writeto(addr: Integer; buf: TPyBytes; stop: Boolean = True): Integer;
    function writevto(addr: Integer; vector: TPyList; stop: Boolean = True): Integer;
    function readfrom(addr, nbytes: Integer; stop: Boolean = True): TPyBytes;
    procedure readfrom_into(addr: Integer; buf: TPyBytes; stop: Boolean = True);
    procedure writeto_mem(addr, memaddr: Integer; buf: TPyBytes; addrsize: Integer = 8);
    function readfrom_mem(addr, memaddr, nbytes: Integer; addrsize: Integer = 8): TPyBytes;
    procedure readfrom_mem_into(addr, memaddr: Integer; buf: TPyBytes; addrsize: Integer = 8);
  private
    FId: Integer;
  end;

  SoftI2C = class(I2C)
  public
    constructor Create(scl: Pin; sda: Pin; freq: Integer = 400000; timeout: Integer = 50000);
  end;

  SPI = class
  public
    const MSB = 0;
    const LSB = 1;
    constructor Create(id: Integer = 1; baudrate: Integer = 1000000; polarity: Integer = 0;
                       phase: Integer = 0; bits: Integer = 8; firstbit: Integer = 0;
                       sck: Pin = nil; mosi: Pin = nil; miso: Pin = nil);
    procedure init(baudrate: Integer = -1; polarity: Integer = -1; phase: Integer = -1;
                   bits: Integer = 8; firstbit: Integer = 0;
                   sck: Pin = nil; mosi: Pin = nil; miso: Pin = nil);
    procedure deinit;
    procedure write(buf: TPyBytes);
    function read(nbytes: Integer; &write: Integer = 0): TPyBytes;
    procedure readinto(buf: TPyBytes; &write: Integer = 0);
    procedure write_readinto(write_buf, read_buf: TPyBytes);
  private
    FId, FBaud, FPol, FPha, FSck, FMosi, FMiso: Integer;
    procedure Open;
  end;

  { MicroPython ESP32's machine.RTC (ports/esp32/machine_rtc.c): the system
    clock as a date. datetime() answers (year, month, day, weekday, hours,
    minutes, seconds, microseconds), weekday 0 being Monday; datetime(t) sets
    it from the same 8-tuple (the weekday in it is ignored, as MicroPython
    ignores it). UTC, because MicroPython has no time zones. The clock starts
    at 1970-01-01 on a fresh boot; nothing here keeps it across a reset
    (a DS3231 is what a program uses for that). }
  RTC = class
  public
    constructor Create(id: Integer = 0);
    function datetime: TPyList; overload;
    procedure datetime(t: TPyList); overload;
    procedure init(t: TPyList);
  end;

{ The width of the next pulse at pulse_level, in microseconds, waiting at most
  timeout_us for it to start and at most timeout_us for it to end. Returns -2
  when it never started and -1 when it never ended; it does not raise. }
function time_pulse_us(pin: Pin; pulse_level: Integer; timeout_us: Integer = 1000000): Integer;

{ Send buf out on pin as a bitstream. encoding 0 is the only one MicroPython
  has: each bit, MSB first, is a high then a low, timed by the 4-tuple of
  nanoseconds (high_0, low_0, high_1, low_1). This is what a WS2812 wants. }
procedure bitstream(pin: Pin; encoding: Integer; timing: TPyList; buf: TPyBytes);

{ Read a DHT11/DHT22's 40 bits into buf[0..4]. OSError ETIMEDOUT when the
  sensor does not answer. dht.py checks the checksum. }
procedure dht_readinto(pin: Pin; buf: TPyBytes);

implementation

const
  ESP_FAIL        = -1;
  ESP_ERR_TIMEOUT = $107;
  MP_ENODEV       = 19;
  MP_ETIMEDOUT    = 110;
  NO_DEVICE_CS    = -1;   { espspi: the program drives CS itself }

{ MicroPython ESP32's mapping of an esp_err_t (machine_i2c.c, mphalport.c)
  and its str() of the OSError it raises. espi2c answers NOT_FOUND when no
  device ACKs its address, which is the ESP_FAIL case under IDF's newer
  driver. }
procedure RaiseEsp(rc: Integer);
var e: Integer; name: AnsiString;
begin
  if (rc = ESP_ERR_TIMEOUT) then e := MP_ETIMEDOUT
  else if (rc = ESP_FAIL) or (rc = I2C_ERR_NOT_FOUND) or (rc = $103) then e := MP_ENODEV
  else e := rc;
  if e = MP_ENODEV then name := 'ENODEV'
  else if e = MP_ETIMEDOUT then name := 'ETIMEDOUT'
  else name := '';
  { (e, name) as args, so a driver's `e.errno == 19` and `e.args[0] == 19`
    both hold, as they do on MicroPython. }
  if name = '' then name := 'Unknown error';
  pyos_raise_errno(e, name);
end;

function PinId(p: Pin): Integer;
begin
  if p = nil then PinId := -1 else PinId := p.id;
end;

{ ---- Pin ------------------------------------------------------------------ }

constructor Pin.Create(id: Integer; mode: Integer; pull: Integer; value: Integer);
begin
  Self.id := id;
  init(mode, pull, value);
end;

procedure Pin.init(mode: Integer; pull: Integer; value: Integer);
begin
  { value first, as MicroPython does, so an output comes up at the level asked
    for instead of glitching through the old one }
  if value >= 0 then GpioSetLevel(id, value and 1);
  if mode = OUT then gpio_output(id)
  else if mode = &IN then gpio_input(id)
  else if mode = OPEN_DRAIN then gpio_opendrain(id);
  if (mode = OUT) and (value >= 0) then GpioSetLevel(id, value and 1);
  if pull = PULL_UP then gpio_pullup(id)
  else if pull = PULL_DOWN then gpio_pulldown(id);
end;

function Pin.value: Integer;
begin
  value := GpioGetLevel(id);
end;

procedure Pin.value(v: Integer);
begin
  if v <> 0 then GpioSetLevel(id, 1) else GpioSetLevel(id, 0);
end;

function Pin.__call__: Integer;
begin
  __call__ := GpioGetLevel(id);
end;

procedure Pin.__call__(v: Integer);
begin
  value(v);
end;

procedure Pin.&on;
begin
  GpioSetLevel(id, 1);
end;

procedure Pin.off;
begin
  GpioSetLevel(id, 0);
end;

{ ---- I2C ------------------------------------------------------------------ }

constructor I2C.Create(id: Integer; scl: Pin; sda: Pin; freq: Integer; timeout: Integer);
begin
  FId := id;
  init(scl, sda, freq, timeout);
end;

procedure I2C.init(scl: Pin; sda: Pin; freq: Integer; timeout: Integer);
var rc: Integer;
begin
  if (scl = nil) or (sda = nil) then
    raise ValueError.Create('I2C: scl and sda pins are required on this port');
  if I2cIsOpen then I2cClose;
  rc := I2cOpen(FId, sda.id, scl.id, freq);
  if rc <> 0 then RaiseEsp(rc);
end;

function I2C.scan: TPyList;
begin
  scan := espi2c.scan;
end;

function I2C.writeto(addr: Integer; buf: TPyBytes; stop: Boolean): Integer;
var rc: Integer;
begin
  rc := I2cWrite(addr, PByte(buf.FData), buf.FLen);
  if rc <> 0 then RaiseEsp(rc);
  writeto := buf.FLen;     { MicroPython: the number of ACKs, one per byte }
end;

function I2C.writevto(addr: Integer; vector: TPyList; stop: Boolean): Integer;
var joined, part: TPyBytes; i: Integer;
begin
  { ONE transaction, as MicroPython does it: a display's control byte and its
    data must share a START, which two writeto calls would not. }
  joined := TPyBytes.Create;
  try
    for i := 0 to vector.count - 1 do
    begin
      part := TPyBytes(vector.at(i));
      if part <> nil then joined.extend(part);
    end;
    writevto := writeto(addr, joined, stop);
  finally
    PXXObjRelease(Pointer(joined));
  end;
end;

function I2C.readfrom(addr, nbytes: Integer; stop: Boolean): TPyBytes;
var rc: Integer;
begin
  Result := TPyBytes.Create(nbytes);
  rc := I2cRead(addr, PByte(Result.FData), nbytes);
  if rc <> 0 then
  begin
    PXXObjRelease(Pointer(Result));
    RaiseEsp(rc);
  end;
end;

procedure I2C.readfrom_into(addr: Integer; buf: TPyBytes; stop: Boolean);
var rc: Integer;
begin
  rc := I2cRead(addr, PByte(buf.FData), buf.FLen);
  if rc <> 0 then RaiseEsp(rc);
end;

{ The register address, big-endian in addrsize/8 bytes, as MicroPython sends it. }
function MemAddr(memaddr, addrsize: Integer; out n: Integer): Int64;
var a: array[0..3] of Byte; i: Integer; r: Int64;
begin
  n := addrsize div 8;
  if (n < 1) or (n > 4) then raise ValueError.Create('I2C: addrsize must be 8, 16, 24 or 32');
  for i := 0 to n - 1 do a[i] := (memaddr shr (8 * (n - 1 - i))) and $FF;
  r := 0;
  Move(a[0], r, n);
  MemAddr := r;
end;

procedure I2C.writeto_mem(addr, memaddr: Integer; buf: TPyBytes; addrsize: Integer);
var wr: TPyBytes; n, rc: Integer; m: Int64;
begin
  m := MemAddr(memaddr, addrsize, n);
  wr := TPyBytes.Create(n + buf.FLen);
  try
    Move(m, PByte(wr.FData)^, n);
    if buf.FLen > 0 then Move(PByte(buf.FData)^, (PByte(wr.FData) + n)^, buf.FLen);
    rc := I2cWrite(addr, PByte(wr.FData), wr.FLen);
  finally
    PXXObjRelease(Pointer(wr));
  end;
  if rc <> 0 then RaiseEsp(rc);
end;

function I2C.readfrom_mem(addr, memaddr, nbytes: Integer; addrsize: Integer): TPyBytes;
begin
  Result := TPyBytes.Create(nbytes);
  try
    readfrom_mem_into(addr, memaddr, Result, addrsize);
  except
    PXXObjRelease(Pointer(Result));
    raise;
  end;
end;

procedure I2C.readfrom_mem_into(addr, memaddr: Integer; buf: TPyBytes; addrsize: Integer);
var n, rc: Integer; m: Int64;
begin
  m := MemAddr(memaddr, addrsize, n);
  rc := I2cWriteRead(addr, @m, n, PByte(buf.FData), buf.FLen);
  if rc <> 0 then RaiseEsp(rc);
end;

constructor SoftI2C.Create(scl: Pin; sda: Pin; freq: Integer; timeout: Integer);
begin
  inherited Create(-1, scl, sda, freq, timeout);
end;

{ ---- SPI ------------------------------------------------------------------ }

constructor SPI.Create(id: Integer; baudrate: Integer; polarity: Integer; phase: Integer;
                       bits: Integer; firstbit: Integer; sck: Pin; mosi: Pin; miso: Pin);
begin
  FId := id;
  FBaud := baudrate;
  FPol := polarity;
  FPha := phase;
  FSck := PinId(sck);
  FMosi := PinId(mosi);
  FMiso := PinId(miso);
  if (bits <> 8) or (firstbit <> MSB) then
    raise ValueError.Create('SPI: only bits=8, firstbit=SPI.MSB on this port');
  Open;
end;

procedure SPI.Open;
var host, rc: Integer;
begin
  if SpiIsOpen then SpiClose;
  { MicroPython ESP32: SPI(1) is SPI2 (HSPI), SPI(2) is SPI3 (VSPI) }
  if FId = 2 then host := SPI2_HOST + 1 else host := SPI2_HOST;
  rc := SpiOpen(host, FSck, FMosi, FMiso);
  if rc = 0 then rc := SpiAddDevice(NO_DEVICE_CS, FBaud, FPol * 2 + FPha);
  if rc <> 0 then RaiseEsp(rc);
end;

procedure SPI.init(baudrate: Integer; polarity: Integer; phase: Integer; bits: Integer;
                   firstbit: Integer; sck: Pin; mosi: Pin; miso: Pin);
begin
  if baudrate > 0 then FBaud := baudrate;
  if polarity >= 0 then FPol := polarity;
  if phase >= 0 then FPha := phase;
  if sck <> nil then FSck := sck.id;
  if mosi <> nil then FMosi := mosi.id;
  if miso <> nil then FMiso := miso.id;
  Open;
end;

procedure SPI.deinit;
begin
  if SpiIsOpen then SpiClose;
end;

procedure SPI.write(buf: TPyBytes);
var rc: Integer;
begin
  if buf.FLen = 0 then Exit;
  rc := SpiWrite(NO_DEVICE_CS, PByte(buf.FData), buf.FLen);
  if rc <> 0 then RaiseEsp(rc);
end;

function SPI.read(nbytes: Integer; &write: Integer): TPyBytes;
var rc: Integer;
begin
  Result := TPyBytes.Create(nbytes);
  if nbytes = 0 then Exit;
  rc := SpiRead(NO_DEVICE_CS, PByte(Result.FData), nbytes, &write);
  if rc <> 0 then
  begin
    PXXObjRelease(Pointer(Result));
    RaiseEsp(rc);
  end;
end;

procedure SPI.readinto(buf: TPyBytes; &write: Integer);
var rc: Integer;
begin
  if buf.FLen = 0 then Exit;
  rc := SpiRead(NO_DEVICE_CS, PByte(buf.FData), buf.FLen, &write);
  if rc <> 0 then RaiseEsp(rc);
end;

procedure SPI.write_readinto(write_buf, read_buf: TPyBytes);
var rc: Integer;
begin
  if write_buf.FLen <> read_buf.FLen then
    raise ValueError.Create('buffers must be the same length');
  if write_buf.FLen = 0 then Exit;
  rc := SpiTransfer(NO_DEVICE_CS, PByte(write_buf.FData), PByte(read_buf.FData), write_buf.FLen);
  if rc <> 0 then RaiseEsp(rc);
end;

{ ---- RTC ------------------------------------------------------------------ }

type
  TRtcTimeval = record      { newlib's struct timeval: 64-bit time_t on IDF 5+ }
    tv_sec: Int64;
    tv_usec: LongInt;
    pad: LongInt;
  end;

function gettimeofday(tv: Pointer; tz: Pointer): Integer; cdecl; external;
function settimeofday(tv: Pointer; tz: Pointer): Integer; cdecl; external;

{ The calendar is mimic_time's (DaysFromCivil / CivilFromDays), so time.gmtime
  and this clock can never disagree about a date. }

constructor RTC.Create(id: Integer);
begin
  inherited Create;
  if id <> 0 then raise ValueError.Create('RTC(' + IntToStr(id) + ') does not exist');
end;

function RTC.datetime: TPyList;
var tv: TRtcTimeval; days, rem, y, m, d: Int64; l: TPyList; v: Variant;
begin
  tv.tv_sec := 0; tv.tv_usec := 0; tv.pad := 0;
  gettimeofday(@tv, nil);
  days := tv.tv_sec div 86400;
  rem := tv.tv_sec - days * 86400;
  if rem < 0 then begin rem := rem + 86400; days := days - 1; end;
  mimic_time.CivilFromDays(days, y, m, d);
  l := TPyList.Create;
  v := y;                       l.append(v);
  v := m;                       l.append(v);
  v := d;                       l.append(v);
  v := ((days mod 7) + 10) mod 7;   { 1970-01-01 was a Thursday: 3 }
                                l.append(v);
  v := rem div 3600;            l.append(v);
  v := (rem div 60) mod 60;     l.append(v);
  v := rem mod 60;              l.append(v);
  v := tv.tv_usec;              l.append(v);
  datetime := pylist_mark_tuple(l);   { tuple(l) would COPY and strand l }
end;

procedure RTC.datetime(t: TPyList);
var tv: TRtcTimeval; y, m, d, hh, mm, ss: Int64;
begin
  if t.count <> 8 then
    raise ValueError.Create('requested length 8 but object has length ' + IntToStr(t.count));
  y := t.at(0); m := t.at(1); d := t.at(2);
  hh := t.at(4); mm := t.at(5); ss := t.at(6);
  tv.tv_sec := mimic_time.DaysFromCivil(y, m, d) * 86400 + hh * 3600 + mm * 60 + ss;
  tv.tv_usec := t.at(7);
  tv.pad := 0;
  settimeofday(@tv, nil);
end;

procedure RTC.init(t: TPyList);
begin
  datetime(t);
end;

{ ---- microsecond pin protocols (espmpyport) -------------------------------- }

function time_pulse_us(pin: Pin; pulse_level: Integer; timeout_us: Integer): Integer;
begin
  time_pulse_us := MpyTimePulseUs(PinId(pin), Ord(pulse_level <> 0), timeout_us);
end;

procedure dht_readinto(pin: Pin; buf: TPyBytes);
begin
  if buf.FLen < 5 then raise ValueError.Create('buffer too small');
  if not MpyDhtReadinto(PinId(pin), PByte(buf.FData)) then
    RaiseEsp(ESP_ERR_TIMEOUT);
end;

{ ---- bitstream, over RMT -------------------------------------------------- }

function rmt_new_tx_channel(cfg: Pointer; ret_chan: Pointer): Integer; external;
function rmt_new_bytes_encoder(cfg: Pointer; ret_enc: Pointer): Integer; external;
function rmt_enable(chan: Pointer): Integer; external;
function rmt_disable(chan: Pointer): Integer; external;
function rmt_del_channel(chan: Pointer): Integer; external;
function rmt_del_encoder(enc: Pointer): Integer; external;
function rmt_transmit(chan: Pointer; enc: Pointer; payload: Pointer;
  bytes: Integer; cfg: Pointer): Integer; external;
function rmt_tx_wait_all_done(chan: Pointer; timeout_ms: Integer): Integer; external;

const
  RMT_CLK_SRC_APB   = 4;          { SOC_MOD_CLK_APB }
  RMT_RESOLUTION_HZ = 40000000;   { MicroPython's: one tick = 25 ns }

type
  { rmt_tx_channel_config_t, rmt_bytes_encoder_config_t and
    rmt_transmit_config_t as IDF v6.0 lays them out; the layout
    examples/esp32/rgb-s3 drives a WS2812 with on silicon. }
  TRmtTxConfig = record
    gpio_num, clk_src, resolution_hz, mem_block_symbols,
    trans_queue_depth, intr_priority, flags: Integer;
  end;
  TRmtBytesEncConfig = record
    bit0, bit1, flags: Integer;
  end;
  TRmtTransmitConfig = record
    loop_count, flags: Integer;
  end;

{ One RMT symbol: a high of hi_ns then a low of lo_ns. The word is
  duration0:15 | level0:1 | duration1:15 | level1:1. }
function RmtSymbol(hi_ns, lo_ns: Int64): Integer;
var hi, lo: Int64;
begin
  { truncating, as MicroPython's (counter_clk_khz * ns) / 1e6 }
  hi := hi_ns * (RMT_RESOLUTION_HZ div 1000000) div 1000;
  lo := lo_ns * (RMT_RESOLUTION_HZ div 1000000) div 1000;
  if (hi < 1) or (lo < 1) or (hi > 32767) or (lo > 32767) then
    raise ValueError.Create('bitstream timing out of range');
  RmtSymbol := Integer(hi or (1 shl 15) or (lo shl 16));
end;

function TxTimeoutMs(timing: TPyList; len: Integer): Integer;
var b0, b1, slow: Int64;
begin
  b0 := Int64(timing.at(0)) + Int64(timing.at(1));
  b1 := Int64(timing.at(2)) + Int64(timing.at(3));
  if b0 > b1 then slow := b0 else slow := b1;
  TxTimeoutMs := (3 * len div 2) * (1 + (8 * slow) div 1000);
end;

procedure bitstream(pin: Pin; encoding: Integer; timing: TPyList; buf: TPyBytes);
var txcfg: TRmtTxConfig; enccfg: TRmtBytesEncConfig; sendcfg: TRmtTransmitConfig;
    chan, enc: Pointer; rc: Integer;
begin
  if encoding <> 0 then raise ValueError.Create('encoding must be 0');
  if timing.count <> 4 then raise ValueError.Create('timing must be a 4-tuple');
  enccfg.bit0 := RmtSymbol(timing.at(0), timing.at(1));
  enccfg.bit1 := RmtSymbol(timing.at(2), timing.at(3));
  enccfg.flags := 1;                  { msb_first }
  sendcfg.loop_count := 0;
  sendcfg.flags := 0;
  txcfg.gpio_num := PinId(pin);
  txcfg.clk_src := RMT_CLK_SRC_APB;
  txcfg.resolution_hz := RMT_RESOLUTION_HZ;
  txcfg.mem_block_symbols := 64;
  txcfg.trans_queue_depth := 1;
  txcfg.intr_priority := 0;
  txcfg.flags := 0;
  { A channel per call, deleted after, as MicroPython's esp32 port does, so
    the pin is free for anything else between writes. }
  chan := nil;
  enc := nil;
  rc := rmt_new_tx_channel(@txcfg, @chan);
  if rc = 0 then rc := rmt_new_bytes_encoder(@enccfg, @enc);
  if rc = 0 then rc := rmt_enable(chan);
  if (rc = 0) and (buf.FLen > 0) then
  begin
    rc := rmt_transmit(chan, enc, buf.FData, buf.FLen, @sendcfg);
    { MicroPython's wait: 50% longer than the stream at its slowest bit }
    if rc = 0 then rc := rmt_tx_wait_all_done(chan, TxTimeoutMs(timing, buf.FLen));
  end;
  if chan <> nil then
  begin
    rmt_disable(chan);
    rmt_del_channel(chan);
  end;
  if enc <> nil then rmt_del_encoder(enc);
  { Deleting the channel disables the pad's output. Hand it back to the GPIO
    matrix driving low, as MicroPython does after its RMT write: level first,
    so the return to GPIO cannot put a stray high on a WS2812 data line. }
  GpioSetLevel(txcfg.gpio_num, 0);
  GpioSetDirection(txcfg.gpio_num, GPIO_MODE_OUTPUT);
  if rc <> 0 then RaiseEsp(rc);
end;

end.
