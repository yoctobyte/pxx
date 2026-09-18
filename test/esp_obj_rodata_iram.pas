{ The two-text-section ESP writer's half of esp_obj_rodata.pas, and the one
  exception to it: a literal an `iram;` routine references DIRECTLY stays in
  writable .data, because iram code is what runs while the flash cache is off
  and IDF places .rodata in flash. The flash-code literal must land in
  .rodata, the iram one in .data -- both asserted, so neither half can pass by
  the other's placement.
  feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident }
program esp_obj_rodata_iram;
var
  s, t: AnsiString;
  EspCount: Integer; cvar;

procedure fast_tick; iram;
begin
  t := 'pxx-iram-marker';
  EspCount := EspCount + Length(t);
end;

begin
  s := 'pxx-rodata-marker';
  fast_tick;
  WriteLn(s, t);
end.
