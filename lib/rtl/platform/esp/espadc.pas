{ SPDX-License-Identifier: Zlib }
unit espadc;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ ESP32 ADC, continuous mode: a "conversion frame done" event for Pascal and
  for Nil Python (feature-esp-gpio-and-adc-callback-slices, slice 3).

  SAME SHAPE AS espgpio's EDGES, deliberately. The IDF driver calls
  on_conv_done from its DMA interrupt. The handler here counts the call and
  pushes interrupts.IntPush(INT_SRC_ADC, channel), and does nothing else: no
  application code, Pascal or Python, runs in interrupt context (the owner's
  design, 2026-09-22). A handler registered with
  `interrupts.on_event(interrupts.INT_SRC_ADC, h)` runs at the next blocking
  point and fetches the samples itself with `read()`, which never waits.

  NO PER-CHIP BIT LAYOUT IS MIRRORED HERE. The DMA result word packs data,
  channel and unit into bitfields whose widths differ per chip; IDF 6's
  adc_continuous_read_parse decodes them into adc_continuous_data_t, which
  is {int unit; int channel; uint32 raw; bool valid} on every chip. The
  structs that ARE mirrored (handle config, config, pattern, callbacks) are
  fixed-width and chip-independent in esp_adc/adc_continuous.h and
  hal/adc_types.h (IDF v6.0.1, read 2026-09-24).

  ADC unit 1 only, one channel, 12 dB attenuation, 12-bit. The callback is
  not IRAM-resident, which the driver accepts unless
  CONFIG_ADC_CONTINUOUS_ISR_IRAM_SAFE is set (the IDF default is unset);
  with it set, registration fails with ESP_ERR_INVALID_ARG and start()
  returns that rc.

  flush_pool is OFF. With it on, the driver's ISR RECEIVES from the same
  ring buffer read() receives from, whenever the pool is full, and a pool that
  a slow Python consumer lets fill is full nearly always. With it off, a full
  pool drops the NEW frame and reports it through on_pool_ovf, which
  overflows() counts. The frame EVENT is pushed either way, so COUNT holds.

  Under qemu the ADC does not work at all (adc_oneshot_new_unit never
  returns, measured 2026-08-30), so this is measured on a board:
  examples/esp32/adc-s3. IDF-only; a project using it needs esp_adc in its
  REQUIRES. }

{$ifdef PXX_NILPY_STR}{$define PXX_NILPY}{$endif}   { PIN BRIDGE: the pinned compiler
  predates PXX_NILPY but sets PXX_NILPY_STR for exactly the same compilations,
  so a NilPy demo built with $(PXX_STABLE) keeps this unit's Python surface.
  Delete this line once a pin carries PXX_NILPY (compiler.pas, fc3cce1eb). }
interface

{$ifdef PXX_NILPY}
uses pylib;   { TPyList, for read(). Under PXX_NILPY only, so a Pascal program
                using this unit does not link the Python runtime (~300 KB,
                past xtensa's CALL8 reach); see interrupts.pas's header. }
{$endif}

{ Pascal surface. Each returns an esp_err_t; 0 is ESP_OK. }
function AdcStart(channel, sampleHz: Integer): Integer;
function AdcStop: Integer;
{ Frames the driver's interrupt has reported since boot, counted by the
  handler before it pushes -- the producer-side count for
  `frames == delivered + dropped`. }
function AdcFrameCount: Integer;
{ Times the driver's internal pool filled (its own overflow callback). }
function AdcPoolOverflows: Integer;

{ ---- the Nil Python surface ----------------------------------------------
      import 'espadc.pas' as adc
      adc.start(0, 20000)      # ADC1 channel 0 at 20 kHz
      adc.read()               # the raw 12-bit samples waiting now, as ints
      adc.stop()                                                              }
function start(channel, sample_hz: Integer): Integer;
function stop: Integer;
{$ifdef PXX_NILPY}
function read: TPyList;
{$endif}
function frames: Integer;
function overflows: Integer;
{ The GPIO pad behind ADC1 channel ch on THIS chip (channel 0 is GPIO1 on the
  S3 and GPIO0 on the C3); -1 if there is none. }
function channel_pad(ch: Integer): Integer;

implementation

uses interrupts;   { IntPush -- the only thing the handler below calls }

type
  TAdcHandleCfg = record        { adc_continuous_handle_cfg_t }
    max_store_buf_size: LongWord;
    conv_frame_size:    LongWord;
    flags:              LongWord;   { bit 0 flush_pool }
  end;
  TAdcPattern = record          { adc_digi_pattern_config_t }
    atten, channel, unitId, bit_width: Byte;
  end;
  TAdcConfig = record           { adc_continuous_config_t }
    pattern_num:    LongWord;
    adc_pattern:    Pointer;
    sample_freq_hz: LongWord;
    conv_mode:      Integer;
    format:         Integer;    { deprecated; the driver picks it per chip }
  end;
  TAdcCbs = record              { adc_continuous_evt_cbs_t }
    on_conv_done: Pointer;
    on_pool_ovf:  Pointer;
  end;
  TAdcData = record             { adc_continuous_data_t }
    unitId:  Integer;
    channel: Integer;
    raw:     LongWord;
    valid:   Byte;
    pad0, pad1, pad2: Byte;
  end;

const
  ADC_UNIT_1             = 0;
  ADC_ATTEN_DB_12        = 3;
  ADC_BITWIDTH_12        = 12;
  ADC_CONV_SINGLE_UNIT_1 = 1;
  FRAME_BYTES            = 256;   { 64 conversions of SOC_ADC_DIGI_DATA_BYTES_PER_CONV = 4 }
  STORE_BYTES            = 1024;
  READ_MAX               = 64;
  ESP_ERR_INVALID_STATE  = $103;

function adc_continuous_new_handle(cfg: Pointer; ret: Pointer): Integer; external;
function adc_continuous_config(h: Pointer; cfg: Pointer): Integer; external;
function adc_continuous_register_event_callbacks(h: Pointer; cbs: Pointer; user: Pointer): Integer; external;
function adc_continuous_start(h: Pointer): Integer; external;
function adc_continuous_stop(h: Pointer): Integer; external;
function adc_continuous_deinit(h: Pointer): Integer; external;
function adc_continuous_read_parse(h: Pointer; data: Pointer; maxSamples: LongWord;
  numSamples: Pointer; timeoutMs: LongWord): Integer; external;
function adc_continuous_channel_to_io(unitId, channel: Integer; io: Pointer): Integer; external;

var
  Handle: Pointer;
  AdcChannel: Integer;
  FrameIsrCount: LongInt;
  PoolOvfCount: LongInt;
  Pattern: TAdcPattern;
  ReadBuf: array[0 .. READ_MAX - 1] of TAdcData;

{ INTERRUPT CONTEXT (the driver's DMA ISR). Counts and pushes, nothing else.
  Returns False: no higher-priority task was woken by us. Each counter has
  exactly one writer, so plain increments suffice. }
function ConvDoneIsr(h: Pointer; edata: Pointer; user: Pointer): Boolean;
begin
  FrameIsrCount := FrameIsrCount + 1;
  IntPush(INT_SRC_ADC, AdcChannel);
  Result := False;
end;

function PoolOvfIsr(h: Pointer; edata: Pointer; user: Pointer): Boolean;
begin
  PoolOvfCount := PoolOvfCount + 1;
  Result := False;
end;

function AdcStart(channel, sampleHz: Integer): Integer;
var
  hcfg: TAdcHandleCfg;
  cfg: TAdcConfig;
  cbs: TAdcCbs;
  h: Pointer;
  rc: Integer;
begin
  if Handle <> nil then
  begin
    AdcStart := ESP_ERR_INVALID_STATE;   { already running; stop() first }
    Exit;
  end;
  hcfg.max_store_buf_size := STORE_BYTES;
  hcfg.conv_frame_size := FRAME_BYTES;
  hcfg.flags := 0;   { no flush_pool: see the header }
  h := nil;
  rc := adc_continuous_new_handle(@hcfg, @h);
  if rc <> 0 then begin AdcStart := rc; Exit; end;

  AdcChannel := channel;
  Pattern.atten := ADC_ATTEN_DB_12;
  Pattern.channel := channel;
  Pattern.unitId := ADC_UNIT_1;
  Pattern.bit_width := ADC_BITWIDTH_12;
  cfg.pattern_num := 1;
  cfg.adc_pattern := @Pattern;
  cfg.sample_freq_hz := sampleHz;
  cfg.conv_mode := ADC_CONV_SINGLE_UNIT_1;
  cfg.format := 0;
  rc := adc_continuous_config(h, @cfg);
  if rc = 0 then
  begin
    cbs.on_conv_done := @ConvDoneIsr;
    cbs.on_pool_ovf := @PoolOvfIsr;
    rc := adc_continuous_register_event_callbacks(h, @cbs, nil);
  end;
  if rc = 0 then
    rc := adc_continuous_start(h);
  if rc <> 0 then
  begin
    adc_continuous_deinit(h);
    AdcStart := rc;
    Exit;
  end;
  Handle := h;
  IntSourceOpen;     { a live source for interrupts' hidden loop }
  AdcStart := 0;
end;

function AdcStop: Integer;
var rc: Integer;
begin
  if Handle = nil then begin AdcStop := ESP_ERR_INVALID_STATE; Exit; end;
  rc := adc_continuous_stop(Handle);
  adc_continuous_deinit(Handle);
  Handle := nil;
  IntSourceClose;
  AdcStop := rc;
end;

function AdcFrameCount: Integer;
begin
  AdcFrameCount := FrameIsrCount;
end;

function AdcPoolOverflows: Integer;
begin
  AdcPoolOverflows := PoolOvfCount;
end;

{ ---- the Nil Python surface ---------------------------------------------- }

function start(channel, sample_hz: Integer): Integer;
begin
  start := AdcStart(channel, sample_hz);
end;

function stop: Integer;
begin
  stop := AdcStop;
end;

{$ifdef PXX_NILPY}
{ What is waiting now, up to READ_MAX samples; timeout 0, so it never blocks
  (ESP_ERR_TIMEOUT with nothing waiting gives an empty list). Invalid samples
  -- the driver's own flag -- are skipped. }
function read: TPyList;
var n: LongWord;
    i: Integer;
    v: Variant;
begin
  Result := TPyList.Create;
  if Handle = nil then Exit;
  n := 0;
  if adc_continuous_read_parse(Handle, @ReadBuf[0], READ_MAX, @n, 0) <> 0 then Exit;
  for i := 0 to Integer(n) - 1 do
    if ReadBuf[i].valid <> 0 then
    begin
      v := Integer(ReadBuf[i].raw);
      Result.append(v);
    end;
end;
{$endif}

function frames: Integer;
begin
  frames := FrameIsrCount;
end;

function overflows: Integer;
begin
  overflows := PoolOvfCount;
end;

function channel_pad(ch: Integer): Integer;
var io: Integer;
begin
  io := -1;
  if adc_continuous_channel_to_io(ADC_UNIT_1, ch, @io) <> 0 then
    io := -1;
  channel_pad := io;
end;

end.
