{ SPDX-License-Identifier: Zlib }
unit esp_finalization_unit;
{ A unit whose FINALIZATION section announces itself, for
  test_esp_finalization_runs.pas. Separate file because a finalization section
  only exists in a unit, and the property under test is that pxx runs it on the
  ESP profile.

  WHY THIS IS WORTH A ROW OF ITS OWN, and not folded into an atexit test:
  NilPy's `atexit` handlers ARE a finalization section (lib/rtl/atexit.pas says
  so in its header -- finalization is what gives CPython's last-registered-first
  order for free). So "atexit does not run on ESP" and "unit finalization does
  not run on ESP" are the same claim wearing different clothes, and the second
  is far broader: every `finalization` in lib/rtl depends on it. Measured
  2026-09-28 on esp32c3 QEMU, this runs; a sweep had reported the atexit test as
  an ESP gap, and it turned out to be the sweep's own output truncation. Had
  this probe existed, one 20 s run would have separated the two readings
  immediately. }
interface

procedure Touch;

implementation

procedure Touch;
begin
  WriteLn('touch');
end;

initialization
  WriteLn('FIN-PROBE init');

finalization
  WriteLn('FIN-PROBE finalization ran');

end.
