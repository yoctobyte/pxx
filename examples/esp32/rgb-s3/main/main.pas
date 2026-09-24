{ SPDX-License-Identifier: 0BSD }
program Esp32S3Rgb;
{ Colour-fading rainbow on the ESP32-S3 devkit's onboard WS2812 RGB LED.

  A WS2812 is not a GPIO LED: it takes 24 bits (G, R, B, MSB first) as
  pulse widths at 800 kHz, so it is driven through the RMT peripheral with
  IDF's bytes encoder -- one RMT symbol per bit, no C wrapper.

  The LED sits on GPIO48 on DevKitC-1 v1.0 and GPIO38 on v1.1, and nothing
  on the board says which, so both pins are driven. }

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
function rmt_new_tx_channel(cfg: Pointer; ret_chan: Pointer): Integer; external;
function rmt_new_bytes_encoder(cfg: Pointer; ret_enc: Pointer): Integer; external;
function rmt_enable(chan: Pointer): Integer; external;
function rmt_transmit(chan: Pointer; enc: Pointer; payload: Pointer;
  bytes: Integer; cfg: Pointer): Integer; external;
function rmt_tx_wait_all_done(chan: Pointer; timeout_ms: Integer): Integer; external;

const
  RMT_CLK_SRC_APB = 4;          { SOC_MOD_CLK_APB, esp32s3 clk_tree_defs.h }
  RESOLUTION_HZ   = 10000000;   { 10 MHz: one tick = 0.1 us }
  { rmt_symbol_word_t = duration0:15 | level0:1 | duration1:15 | level1:1.
    WS2812 bit 0: 0.3 us high, 0.9 us low; bit 1: 0.9 us high, 0.3 us low. }
  SYM_BIT0 = 3 or (1 shl 15) or (9 shl 16);
  SYM_BIT1 = 9 or (1 shl 15) or (3 shl 16);
  BRIGHT   = 40;                { of 255 -- a devkit WS2812 at full is blinding }
  NPINS    = 2;

type
  { rmt_tx_channel_config_t, IDF v6.0 -- all fields 32-bit on xtensa. }
  TRmtTxConfig = record
    gpio_num, clk_src, resolution_hz, mem_block_symbols,
    trans_queue_depth, intr_priority, flags: Integer;
  end;
  { rmt_bytes_encoder_config_t }
  TBytesEncConfig = record
    bit0, bit1, flags: Integer;
  end;
  { rmt_transmit_config_t }
  TTransmitConfig = record
    loop_count, flags: Integer;
  end;

var
  pins: array[0..NPINS - 1] of Integer;
  chans, encs: array[0..NPINS - 1] of Pointer;
  grb: array[0..2] of Byte;
  txcfg: TRmtTxConfig;
  enccfg: TBytesEncConfig;
  sendcfg: TTransmitConfig;
  i, hue, seg, f, r, g, b, cycles: Integer;

procedure Show(r, g, b: Integer);
var
  k: Integer;
begin
  grb[0] := g * BRIGHT div 255;
  grb[1] := r * BRIGHT div 255;
  grb[2] := b * BRIGHT div 255;
  for k := 0 to NPINS - 1 do
    if chans[k] <> nil then
    begin
      rmt_transmit(chans[k], encs[k], @grb, 3, @sendcfg);
      rmt_tx_wait_all_done(chans[k], 100);
    end;
end;

begin
  pins[0] := 48;
  pins[1] := 38;

  enccfg.bit0 := SYM_BIT0;
  enccfg.bit1 := SYM_BIT1;
  enccfg.flags := 1;             { msb_first }
  sendcfg.loop_count := 0;
  sendcfg.flags := 0;

  for i := 0 to NPINS - 1 do
  begin
    chans[i] := nil;
    txcfg.gpio_num := pins[i];
    txcfg.clk_src := RMT_CLK_SRC_APB;
    txcfg.resolution_hz := RESOLUTION_HZ;
    txcfg.mem_block_symbols := 64;
    txcfg.trans_queue_depth := 4;
    txcfg.intr_priority := 0;
    txcfg.flags := 0;
    if (rmt_new_tx_channel(@txcfg, @chans[i]) = 0)
       and (rmt_new_bytes_encoder(@enccfg, @encs[i]) = 0)
       and (rmt_enable(chans[i]) = 0) then
      esp_rom_printf('PXX rgb: WS2812 channel up on GPIO%d'#10, pins[i])
    else
    begin
      esp_rom_printf('PXX rgb: RMT setup FAILED on GPIO%d'#10, pins[i]);
      chans[i] := nil;
    end;
  end;

  { Hue wheel of 768 steps: red -> green -> blue -> red. }
  cycles := 0;
  hue := 0;
  while True do
  begin
    seg := hue div 256;
    f := hue mod 256;
    if seg = 0 then
    begin r := 255 - f; g := f; b := 0; end
    else if seg = 1 then
    begin r := 0; g := 255 - f; b := f; end
    else
    begin r := f; g := 0; b := 255 - f; end;
    Show(r, g, b);
    vTaskDelay(2);               { 20 ms at CONFIG_FREERTOS_HZ=100 }
    hue := hue + 4;
    if hue >= 768 then
    begin
      hue := 0;
      cycles := cycles + 1;
      esp_rom_printf('PXX rgb: rainbow cycle %d'#10, cycles);
    end;
  end;
end.
