{ SPDX-License-Identifier: 0BSD }
program EspNvsCheck;
{ SETTINGS THAT SURVIVE A REBOOT, CHECKED ACROSS REBOOTS.

  lib/rtl/platform/esp/espnvs.pas keeps key/value pairs in the flash's NVS
  partition. A value read back in the same boot proves nothing about flash, so
  this program checks each claim in the NEXT boot. It walks phases, keeping
  the phase itself (and the failure count) in NVS:

    phase 0  a clean slate: every key erased, so an absent key answers its
             default with ESP_ERR_NVS_NOT_FOUND; a 16-character key is
             refused. Writes an Int64 above 2^32, a string, a boot count;
             commits; esp_restart.
    phase 1  after the SOFTWARE reboot: the three values read back exactly.
             Erases the string, commits, esp_restart.
    phase 2  the erased string stays erased across the reboot -- the control
             that phase 1's reads came from flash and not from something that
             merely was never cleared. Writes a value for the next phase and
             STOPS: the next boot must come from outside.
    phase 3  after a HARDWARE reset (the reset line, or unplugging the board):
             that value is there. Prints NVS-CHECK-DONE with the failures
             counted across all four boots, and sets phase 0 again.

  So one run is: flash (boots phases 0, 1, 2), then reset the board once.
  Each row prints PASS or FAIL. }

uses espnvs;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
procedure esp_restart; external;

const
  BIG = Int64(1099511627779);   { 2^40 + 3: needs all 64 bits of the store }
  NAME = 'written-before-reboot';

var
  Fails: Integer;

procedure Row(name: string; ok: Boolean; detail: Integer);
begin
  esp_rom_printf(name, 0);
  if ok then esp_rom_printf(' PASS (%d)'#10, detail)
  else begin esp_rom_printf(' FAIL (%d)'#10, detail); Fails := Fails + 1; end;
end;

{ Record this boot's failures and move to the next phase, durably. }
procedure Advance(next: Integer);
begin
  NvsSetInt('fails', NvsGetInt('fails', 0) + Fails);
  NvsSetInt('phase', next);
  NvsCommit;
end;

var phase: Integer; v: Int64; s: string;
begin
  vTaskDelay(10);
  phase := NvsGetInt('phase', 0);
  esp_rom_printf('NVS-CHECK phase %d'#10, phase);
  case phase of
    1:
      begin
        v := NvsGetInt('big', -1);
        Row('big after reboot', v = BIG, Integer(v and $7FFFFFFF));
        s := NvsGetStr('name', 'absent');
        Row('string after reboot', s = NAME, Length(s));
        Row('boots after reboot', NvsGetInt('boots', 0) = 1, NvsGetInt('boots', 0));
        Row('erase', NvsErase('name') = 0, NvsLastError);
        Advance(2);
        esp_restart;
      end;
    2:
      begin
        s := NvsGetStr('name', 'absent');
        Row('erased stays erased', (s = 'absent') and (NvsLastError = NVS_ERR_NOT_FOUND), NvsLastError);
        Row('big still there', NvsGetInt('big', -1) = BIG, 0);
        Row('arm hardware reset', NvsSetInt('survivor', 4242) = 0, NvsLastError);
        Advance(3);
        esp_rom_printf('NVS-CHECK waiting: reset the board for phase %d'#10, 3);
      end;
    3:
      begin
        Row('after hardware reset', NvsGetInt('survivor', 0) = 4242, NvsGetInt('survivor', 0));
        Fails := Fails + NvsGetInt('fails', 0);
        esp_rom_printf('NVS-CHECK-DONE failed=%d'#10, Fails);
        NvsSetInt('fails', 0);
        NvsSetInt('phase', 0);
        NvsCommit;
      end;
  else
    begin
      { phase 0, or anything unexpected: start clean }
      NvsErase('big'); NvsErase('name'); NvsErase('boots');
      NvsErase('survivor'); NvsErase('fails');
      NvsCommit;
      v := NvsGetInt('big', 77);
      Row('absent gives default', (v = 77) and (NvsLastError = NVS_ERR_NOT_FOUND), NvsLastError);
      s := NvsGetStr('name', 'dflt');
      Row('absent string default', s = 'dflt', Length(s));
      Row('long key refused', NvsSetInt('sixteen-chars-xx', 1) = NVS_ERR_KEY_TOO_LONG, NvsLastError);
      Row('set big', NvsSetInt('big', BIG) = 0, NvsLastError);
      Row('set string', NvsSetStr('name', NAME) = 0, NvsLastError);
      Row('set boots', NvsSetInt('boots', 1) = 0, NvsLastError);
      Advance(1);
      esp_restart;
    end;
  end;
  while True do vTaskDelay(1000);
end.
