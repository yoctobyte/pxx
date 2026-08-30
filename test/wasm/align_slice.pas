program AlignSlice;
{ The WASI out-parameters whose ALIGNMENT the spec constrains, exercised so a
  strict host can refuse them.

  WASI preview1 declares `fd_seek`'s returned `filesize` and
  `clock_time_get`'s `timestamp` as u64, and a host may require the pointer it
  writes them through to be 8-byte aligned. wasmtime does; node's WASI does
  not. So this slice is not interesting under node at all — it is written to be
  run under BOTH, and the check that owns it says why.

  Getting the alignment wrong is not a near miss. symtab.inc's TypeAlign aligns
  a global to its ELEMENT type, so `array[0..15] of Byte` — the obvious shape
  for a scratch buffer, and the one both WASI backends used — is aligned to
  ONE. It happened to land 4-aligned in the compiler's own module, which is why
  every existing slice passed and only a 7 MB module built from compiler.pas
  ever tripped it.

  Both copies of the capability model are covered on purpose, because there are
  two and they can drift (see
  bug-a-two-copies-of-the-wasi-capability-model-one-in-the-pal-one-in-wasibackend):

    * LoadFile  -> PXXWasiLoadFile -> wasi_fd_seek, in
                   compiler/builtin/wasibackend.pas — the copy that actually
                   broke, because it is the one the wasm-hosted COMPILER uses;
    * PalSeek   -> PalBackendSeek  -> wasi_fd_seek,
      PalRealtime / PalMonotonicMillis -> wasi_clock_time_get, in
                   lib/rtl/platform/wasi/platform_backend.pas — never observed
                   failing, and holding the identical defect.

  The clocks are asserted as PROPERTIES, not against an oracle: a timestamp
  cannot be diffed against a native run. What a misaligned or unwritten
  out-param actually produces is zero, so "after 2000" and "monotonic does not
  go backwards" are the assertions that fail on the real defect while staying
  true forever otherwise. }

uses platform;

var
  s, path: AnsiString;
  fd: Integer;
  endPos, backPos: Int64;
  sec, nsec: Int64;
  m0, m1: Int64;
  i: Integer;

begin
  { --- wasibackend's fd_seek, through the LoadFile builtin ----------------- }
  s := '';
  path := 'align_data.txt';
  LoadFile(path, s);
  Writeln('loadfile-len=', Length(s));
  Writeln('loadfile-body=', s);

  { --- the PAL's fd_seek --------------------------------------------------- }
  fd := PalOpen(PChar(path), 0, 0);       { O_RDONLY }
  if fd < 0 then
    Writeln('palopen=FAILED')
  else
  begin
    endPos  := PalSeek(fd, 0, 2);              { SEEK_END -> the file's size }
    backPos := PalSeek(fd, 0, 0);              { SEEK_SET -> 0 }
    Writeln('palseek-end=', endPos);
    Writeln('palseek-set=', backPos);
    PalClose(fd);
  end;

  { --- the PAL's clock_time_get, both clocks ------------------------------- }
  sec := 0; nsec := 0;
  if PalRealtime(sec, nsec) <> 0 then
    Writeln('realtime=FAILED')
  else
    { A zero out-param is what an unwritten one looks like, so the assertion is
      "later than 2000", not "equal to" anything. 946684800 = 2000-01-01Z. }
    Writeln('realtime-after-2000=', sec > 946684800);

  { NOT `m0 > 0`. That was the first version of this line and it is WRONG in a
    way worth recording: wasmtime's monotonic clock starts near zero at process
    start, node's does not, so a fast program legitimately reads 0 milliseconds
    on one host and not the other. It is a difference between HOSTS, not a
    defect, and asserting it made this slice fail on correct code the first time
    it met a second host. Monotonicity is the property that is actually
    promised; the magnitude is not. }
  m0 := PalMonotonicMillis;
  for i := 1 to 200000 do s := s;              { burn a little wall clock }
  m1 := PalMonotonicMillis;
  Writeln('monotonic-forward=', m1 >= m0);
  Writeln('monotonic-sane=', (m0 >= 0) and (m1 - m0 < 3600000));
end.
