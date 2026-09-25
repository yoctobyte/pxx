{ SPDX-License-Identifier: 0BSD }
program EspSpiMaster;
{ THE SPI MASTER, TESTED ON ONE BOARD WITH NO DEVICE AND NO WIRE.

  SPI2 (FSPI) through lib/rtl/platform/esp/espspi.pas, the unit under test,
  on the S3's IOMUX pins for that controller: SCK 12, MOSI 11, MISO 13, CS 10.
  Nothing need be connected to them.

  An SPI master cannot tell whether anyone is listening -- there is no ACK --
  so "a transfer to an unconnected device" completes with ESP_OK, and the
  question worth asking is whether the bytes on the wire are the right ones.
  Three rows answer that without a device:

    pull-up / pull-down   with MISO held high by the pad's own pull-up, a read
                          returns $FF bytes; with the pull-down, $00. A read
                          that never sampled the pin cannot produce both.
    one-pad loopback      the bus reopened with MISO on the MOSI pad (GPIO
                          11). The GPIO matrix feeds the pad's own output back
                          into the controller's MISO input, so full duplex
                          reads back what it sent: the jumper MOSI->MISO would
                          be, inside the chip. Every length 1..8 is sent too,
                          into an aligned and an odd address, because the
                          driver DMAs into one and bounces the other. The
                          pull-down row is this row's control: there MOSI
                          sends $FF on pad 11 and MISO on pad 13 reads $00,
                          so nothing echoes between separate pads.
    timing                1024 bytes written at 1 MHz and at 8 MHz. SPI has
                          no clock stretching, so the time is fixed by the
                          clock: >= 8192 us and >= 1024 us, and not much more.
                          A transfer that returned early, or that ran at the
                          wrong clock, fails one bound or the other.

  The other rows: a second open is refused, a transfer to a CS nobody added
  answers ESP_ERR_NOT_FOUND, the driver reports the clock it set, and close.
  Each prints PASS or FAIL; the last line is SPI-MASTER-DONE with the count.

  ON A BOARD, from the repo root:
    tools/esp_flash.sh --project examples/esp32/spi-s3 --port /dev/ttyACM0
  Measured 2026-09-25 on an ESP32-S3 (rev v0.2), pin v425: 18 passed, 0
  failed; the 1024-byte writes took 8255 us at 1 MHz and 1071 us at 8 MHz.
  Under qemu (./build.sh qemu-assert) only the first seven lines run. }

uses espspi;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
function esp_timer_get_time: Int64; external;
function gpio_set_pull_mode(pin, mode: Integer): Integer; external;

const
  SCK = 12;
  MOSI = 11;
  MISO = 13;
  CS = 10;
  GPIO_PULLUP_ONLY = 0;
  GPIO_PULLDOWN_ONLY = 1;
  N_TIMED = 1024;

var
  Passed, Failed: Integer;
  Big: array[0 .. N_TIMED - 1] of Byte;
  GW, GR: array[0 .. 15] of Byte;

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

function AllAre(p: PByte; n, v: Integer): Boolean;
var i: Integer;
begin
  AllAre := True;
  for i := 0 to n - 1 do
    if p[i] <> v then AllAre := False;
end;

{ Microseconds for one write of N_TIMED bytes to device cs. }
function TimedWrite(cs: Integer; var rc: Integer): Integer;
var t0: Int64;
begin
  t0 := esp_timer_get_time;
  rc := SpiWrite(cs, @Big[0], N_TIMED);
  TimedWrite := esp_timer_get_time - t0;
end;

var
  rc, i, us, khz, n, off, m: Integer;
  rd: array[0 .. 7] of Byte;
  wr: array[0 .. 7] of Byte;
begin
  esp_rom_printf('SPI-MASTER SPI2 SCK=%d', SCK);
  esp_rom_printf(' MOSI=%d', MOSI);
  esp_rom_printf(' MISO=%d, no device, no wire'#10, MISO);

  rc := SpiOpen(SPI2_HOST, SCK, MOSI, MISO);
  Row('open', rc = 0, rc);
  rc := SpiOpen(SPI2_HOST, SCK, MOSI, MISO);
  Row('open twice refused', rc = SPI_ERR_NOT_OPEN, rc);
  rc := SpiWrite(CS, @wr[0], 1);
  Row('unknown cs', rc = SPI_ERR_NOT_FOUND, rc);

  rc := SpiAddDevice(CS, 1000000, 0);
  Row('device 1 MHz', rc = 0, rc);
  khz := SpiActualKHz(CS);
  Row('actual clock', khz = 1000, khz);
  rc := SpiAddDevice(-1, 8000000, 0);      { a second device, CS left to the program }
  Row('device 8 MHz', rc = 0, rc);

  gpio_set_pull_mode(MISO, GPIO_PULLUP_ONLY);
  for i := 0 to 7 do rd[i] := $5A;
  rc := SpiRead(CS, @rd[0], 8, 0);
  Row('read, no device, rc', rc = 0, rc);
  Row('read pulled up', AllAre(@rd[0], 8, $FF), rd[0]);
  gpio_set_pull_mode(MISO, GPIO_PULLDOWN_ONLY);
  for i := 0 to 7 do rd[i] := $5A;
  rc := SpiRead(CS, @rd[0], 8, $FF);
  Row('read pulled down', (rc = 0) and AllAre(@rd[0], 8, 0), rd[0]);

  for i := 0 to N_TIMED - 1 do Big[i] := i;
  us := TimedWrite(CS, rc);
  Row('write 1024 B @1 MHz rc', rc = 0, rc);
  Row('write 1024 B @1 MHz us', (us >= 8192) and (us < 8192 + 2000), us);
  us := TimedWrite(-1, rc);
  Row('write 1024 B @8 MHz us', (rc = 0) and (us >= 1024) and (us < 1024 + 1000), us);

  rc := SpiClose;
  Row('close', rc = 0, rc);

  { MISO on the MOSI pad: the loopback jumper, inside the chip. }
  rc := SpiOpen(SPI2_HOST, SCK, MOSI, MOSI);
  Row('open one-pad', rc = 0, rc);
  if rc = 0 then
  begin
    rc := SpiAddDevice(CS, 1000000, 0);
    wr[0] := $A5; wr[1] := $5A; wr[2] := $01; wr[3] := $80;
    wr[4] := $FF; wr[5] := $00; wr[6] := $3C; wr[7] := $C3;
    for i := 0 to 7 do rd[i] := 0;
    if rc = 0 then rc := SpiTransfer(CS, @wr[0], @rd[0], 8);
    Row('loopback rc', rc = 0, rc);
    rc := 0;
    for i := 0 to 7 do if rd[i] <> wr[i] then rc := rc + 1;
    Row('loopback bytes', rc = 0, rd[0] * 256 + rd[1]);
    { Every length 1..8 at an aligned and an odd receive address: the driver
      DMAs straight into an aligned buffer and bounces an unaligned one, and
      both paths have to land the bytes. }
    m := 0;
    for n := 1 to 8 do
      for off := 0 to 1 do
      begin
        for i := 0 to 15 do begin GW[i] := $40 + n * 16 + i; GR[i] := 0; end;
        if SpiTransfer(CS, @GW[0], @GR[off], n) <> 0 then m := m + 1;
        for i := 0 to n - 1 do if GR[off + i] <> GW[i] then m := m + 1;
      end;
    Row('loopback lengths 1-8, odd and even address', m = 0, m);
    rc := SpiClose;
    Row('close one-pad', rc = 0, rc);
  end;

  esp_rom_printf('SPI-MASTER-DONE passed=%d', Passed);
  esp_rom_printf(' failed=%d'#10, Failed);
  while True do vTaskDelay(1000);
end.
