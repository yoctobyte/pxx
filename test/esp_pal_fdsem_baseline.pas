program esp_pal_fdsem_baseline;
{ BASELINE for feature-pal-esp-posix-fd-semantics, and it exists to be diffed
  against after the rewrite to exact POSIX fd semantics.

  WHY IT IS BUILT FOR THE ESP TARGETS AND NOT RUN ON THE HOST. The ticket's own
  "one thing IS doable without hardware" note says to write host-side
  `--platform=esp` tests pinning the current behaviour. Measured 2026-09-02:
  that would pin the WRONG POPULATION. The entire stdio/IDF implementation in
  lib/rtl/platform/esp/platform_backend.pas sits under
  {$ifdef PXX_PAL_ESP_IDF_TARGET}, which is defined only for CPU_XTENSA and
  CPU_RISCV32 (lines 160-161). On an x86-64 host with `--platform=esp` that arm
  is compiled OUT, so every PAL file call returns PAL_ERR_UNSUPPORTED from the
  stub -- open of a writable path included, which the real arm would have
  succeeded at. A host test asserting -38 would pass before AND after the
  rewrite while saying nothing about either.

  So the baseline is an OBJECT built for the two ESP targets, where the real arm
  is what compiles. The assertion that makes it a baseline rather than a
  smoke test is the SYMBOL IMPORT: the object must reference the newlib stdio
  surface the current implementation is written on. That is what pins "this is
  still the stdio-backed path" -- and it is exactly what must CHANGE when the
  rewrite moves to direct open/read/write, so the row is expected to fail then
  and be updated deliberately rather than silently keep passing. }
uses platform;
function esp_pal_probe(dummy: Integer): Integer; cdecl;
var fd: Integer; buf: array[0..7] of Char;
begin
  { every call below is here to force its backend routine to be emitted }
  fd := PalOpen('/probe.txt', PAL_OPEN_CREATE or PAL_OPEN_WRITE, 420);
  PalWrite(fd, @buf[0], 1);
  PalSeek(fd, 0, 0);
  PalRead(fd, @buf[0], 1);
  PalFlush(fd);
  PalClose(fd);
  { and the refusal the ticket names first: EXCL is an explicit
    PAL_ERR_UNSUPPORTED inside the IDF arm, not merely absent }
  Result := PalOpen('/probe2.txt', PAL_OPEN_CREATE or PAL_OPEN_EXCL or PAL_OPEN_WRITE, 420);
end;

begin
  { the object is the deliverable; the program body is never reached on device }
end.
