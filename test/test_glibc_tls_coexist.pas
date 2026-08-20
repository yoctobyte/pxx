program test_glibc_tls_coexist;
{ pxx's own thread pointer must not evict libc's.

  Every x86-64 pxx binary installs a TLS block at its ELF entry point so
  __pxxTlsBase works on the main thread. The first version of that used `fs` --
  which is exactly where glibc and musl keep THEIR thread pointer. A pxx program
  that links libc (`external 'libc.so.6'`) then lost errno, the stack-protector
  canary at fs:0x28, locale and stdio in one instruction, and this four-line
  program segfaulted before printing anything. `pinned` ran it fine.

  Nothing caught it: no test in the quick tier links glibc, and
  test_multithreading (which links libpthread) survived by luck -- its glibc
  calls happened not to touch the clobbered fields. So this test exists to make
  the coexistence explicit rather than incidental.

  strerror is the sharp one: it reads locale and errno, both fs-relative, and
  returns a pointer into libc's per-thread storage. malloc exercises glibc's own
  arena TLS. If pxx ever moves its block back to fs, this stops printing.

  x86-64 Linux keeps gs unused in userspace, which is the whole reason the two
  can coexist. }

function strerror(e: Integer): PChar; cdecl; external 'libc.so.6';
function malloc(n: NativeInt): Pointer; cdecl; external 'libc.so.6';
procedure free(p: Pointer); cdecl; external 'libc.so.6';

var
  p: Pointer;
  ok: Boolean;
begin
  ok := True;
  p := malloc(4096);
  if p = nil then ok := False;
  free(p);
  { errno + locale, both through libc's thread pointer. The TEXT is
    locale-dependent, so assert that it is a real non-empty string rather than
    pinning words that differ per machine. }
  if strerror(2) = nil then ok := False
  else if strerror(2)^ = #0 then ok := False;
  { and OUR thread pointer still works, on the same thread, at the same time }
  if __pxxTlsBase = nil then ok := False;
  if PInt64(__pxxTlsBase)^ <> Int64(PtrUInt(__pxxTlsBase)) then ok := False;
  if ok then Writeln('GLIBC TLS COEXIST OK') else Writeln('GLIBC TLS COEXIST BAD');
end.
