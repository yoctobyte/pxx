{ SPDX-License-Identifier: 0BSD }
program GpioProbe;
{ PROBE, not a deliverable: does Espressif QEMU's esp32c3 GPIO model actually
  deliver an edge interrupt? Drives a pin configured INPUT_OUTPUT from software
  and counts ISR entries. Raw SDK calls on purpose -- this answers whether
  slice 2 can be WITNESSED here before any library is written against it. }

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
function gpio_config(cfg: Pointer): Integer; external;
function gpio_install_isr_service(flags: Integer): Integer; external;
function gpio_isr_handler_add(pin: Integer; isr: Pointer; arg: Pointer): Integer; external;
function gpio_set_level(pin: Integer; level: Integer): Integer; external;
function gpio_get_level(pin: Integer): Integer; external;

const
  PIN                    = 8;
  GPIO_MODE_INPUT_OUTPUT = 3;   { BIT0 input | BIT1 output }
  GPIO_INTR_ANYEDGE      = 3;

type
  { gpio_config_t on C3: uint64 then four ints. No hys_ctrl_mode -- that field
    is guarded by SOC_GPIO_SUPPORT_PIN_HYS_FILTER, undefined for esp32c3. }
  TGpioConfig = record
    pin_bit_mask: Int64;
    mode:         Integer;
    pull_up_en:   Integer;
    pull_down_en: Integer;
    intr_type:    Integer;
  end;

var
  edges: Integer;

procedure OnEdge(arg: Pointer);
begin
  edges := edges + 1;
end;

var
  cfg: TGpioConfig;
  rc, i, lvl: Integer;
begin
  edges := 0;

  cfg.pin_bit_mask := Int64(1) shl PIN;
  cfg.mode         := GPIO_MODE_INPUT_OUTPUT;
  cfg.pull_up_en   := 0;
  cfg.pull_down_en := 0;
  cfg.intr_type    := GPIO_INTR_ANYEDGE;

  rc := gpio_config(@cfg);
  esp_rom_printf('PROBE: gpio_config rc=%d'#10, rc);

  rc := gpio_install_isr_service(0);
  esp_rom_printf('PROBE: install_isr_service rc=%d'#10, rc);

  rc := gpio_isr_handler_add(PIN, @OnEdge, nil);
  esp_rom_printf('PROBE: isr_handler_add rc=%d'#10, rc);

  { toggle the pin from software; an INPUT_OUTPUT pin feeds its own input path }
  for i := 1 to 5 do
  begin
    rc  := gpio_set_level(PIN, 1);
    vTaskDelay(5);
    lvl := gpio_get_level(PIN);
    esp_rom_printf('PROBE: set 1 -> read %d'#10, lvl);
    rc  := gpio_set_level(PIN, 0);
    vTaskDelay(5);
    lvl := gpio_get_level(PIN);
    esp_rom_printf('PROBE: set 0 -> read %d'#10, lvl);
  end;

  { CONTROL: a pull-up on an INPUT-only pin reads 1 on real silicon with
    nothing attached. If this also reads 0, the input path is not modelled at
    all, and the edges=0 above is explained by that rather than by a missing
    interrupt model -- two different limits with two different workarounds. }
  cfg.pin_bit_mask := Int64(1) shl 4;
  cfg.mode         := 1;              { GPIO_MODE_INPUT }
  cfg.pull_up_en   := 1;
  cfg.pull_down_en := 0;
  cfg.intr_type    := 0;              { GPIO_INTR_DISABLE }
  rc := gpio_config(@cfg);
  vTaskDelay(5);
  esp_rom_printf('PROBE: pullup-input pin4 cfg rc=%d', rc);
  esp_rom_printf(' reads %d (1 on real silicon)'#10, gpio_get_level(4));

  esp_rom_printf('PROBE: edges=%d'#10, edges);
  if edges > 0 then
    esp_rom_printf('PROBE: VERDICT qemu-delivers-gpio-edges'#10, 0)
  else
    esp_rom_printf('PROBE: VERDICT qemu-delivers-NO-gpio-edges'#10, 0);

  while True do vTaskDelay(1000);
end.
