program test_elfdynsym;
{$mode objfpc}{$H+}

{ THE REFUSAL ARMS OF compiler/elfdynsym.inc, WHICH NO HEADER CAN REACH.

  The compiler uses this reader to decide whether the library a header's
  DIRECTORY names is one that actually answers -- see LdCacheDirCandidate in
  pasparser_proc.inc. Driven through the compiler's front door, three of its
  guards can only ever be observed ACCEPTING:

    * ElfIsNative64's refusal. Measured 2026-09-10: of 250 /etc/ld.so.cache
      keys with more than one entry, every one lists its x86-64 entry FIRST
      (sole exception: ld-linux.so.2, which no header directory can name). So
      the scan takes the right architecture by cache ORDER on this box and the
      class byte is never what decided it -- while remaining the ONLY thing
      that separates the twins, both of which export SDL_Init.
    * The SHN_UNDEF skip. A .dynsym lists what a library IMPORTS as well as
      what it defines; an implementation ignoring st_shndx accepts any library
      that merely CALLS the function, and every accept row still passes.
    * The bounds checks, which want a malformed file no distribution ships.

  Each row below is a PAIR over one variable: same key with two paths, same
  symbol in two libraries, same library with two symbols. A single-sided row
  would pass just as well against a reader that refuses everything.

  Rows needing a library on this box establish its PRESENCE as a precondition
  and BRANCH on it, so a box without it SKIPS rather than passes -- a control
  that is absent is not a control that succeeded. The last three rows build
  their own input and therefore always run, which is what stops an
  all-skipped run from reporting green.
  feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym }

uses SysUtils;

const
  SDL64 = '/usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0';
  SDL32 = '/usr/lib/i386-linux-gnu/libSDL2-2.0.so.0';
  LIBC  = '/usr/lib/x86_64-linux-gnu/libc.so.6';
  LIBNET= '/usr/lib/x86_64-linux-gnu/libnet.so.9';

var
  DynSymMemoPath: AnsiString = '';
  DynSymMemoBody: AnsiString = '';
  Failures: Integer = 0;
  Ran: Integer = 0;
  Skipped: Integer = 0;

procedure LoadFile(const path: AnsiString; var dst: AnsiString);
{ READ-ONLY, and FileMode is the whole reason this is spelled out. Reset on a
  typed file opens READ/WRITE by default, and every library this harness reads
  is root-owned, so the plain spelling returns IOResult 5 on all of them and
  LoadFile hands back an empty string. Measured while writing this file: with
  that bug in place every REFUSAL row passed and every ACCEPT row failed --
  a reader that refuses everything, which is exactly the shape the paired rows
  below exist to catch, and they caught it in their own harness first. }
var f: file of Byte; n: Int64; buf: array of Byte; i: Int64; savedMode: Byte;
begin
  dst := '';
  savedMode := FileMode;
  FileMode := 0;
  {$I-} Assign(f, path); Reset(f); {$I+}
  FileMode := savedMode;
  if IOResult <> 0 then Exit;
  n := FileSize(f);
  if n > 0 then
  begin
    SetLength(buf, n);
    BlockRead(f, buf[0], n);
    SetLength(dst, n);
    for i := 0 to n - 1 do dst[i + 1] := Chr(buf[i]);
  end;
  Close(f);
end;

{$include ../compiler/elfdynsym.inc}

function Present(const path: AnsiString): Boolean;
begin
  Present := FileExists(path);
end;

procedure Check(const name: AnsiString; got, want: Boolean);
begin
  Inc(Ran);
  if got = want then
    writeln('  ok   ', name)
  else
  begin
    writeln('  FAIL ', name, ' -- got ', got, ', want ', want);
    Inc(Failures);
  end;
end;

procedure Skip(const name, why: AnsiString);
begin
  Inc(Skipped);
  writeln('  SKIP ', name, ' -- ', why);
end;

var
  tmp: AnsiString;
  fh: file of Byte;
  i: Integer;
  body: AnsiString;

begin
  writeln('test_elfdynsym: the refusal arms of the .dynsym reader');

  { ===== PAIR 1: the class byte, one cache key and two paths ===============
    libSDL2-2.0.so.0 is ONE key in /etc/ld.so.cache with an entry per
    architecture. Both twins export SDL_Init, so the symbol check cannot tell
    them apart and this byte is the whole of the discrimination. Asserting only
    the refusal would pass against a reader that rejects every file; asserting
    only the accept would pass against one that rejects none. }
  if Present(SDL64) and Present(SDL32) then
  begin
    LoadFile(SDL64, body);
    Check('native  x86-64 libSDL2-2.0.so.0 is ELFCLASS64', ElfIsNative64(body), True);
    LoadFile(SDL32, body);
    Check('REFUSED i386   libSDL2-2.0.so.0 is not', ElfIsNative64(body), False);
    Check('        ...and the i386 twin exports SDL_Init all the same',
          ElfSoExportsSymbol(SDL32, 'SDL_Init'), False);
    Check('        ...while the x86-64 twin is accepted for it',
          ElfSoExportsSymbol(SDL64, 'SDL_Init'), True);
  end
  else
    Skip('the libSDL2 architecture pair',
         'needs BOTH ' + SDL64 + ' and its i386 twin; one is absent');

  { ===== PAIR 2: SHN_UNDEF, one symbol and two libraries ==================
    libSDL2 CALLS memcmp and libc DEFINES it, so both name it in .dynsym. A
    reader that ignores st_shndx answers True twice and every accept row in
    this file still passes. }
  if Present(SDL64) and Present(LIBC) then
  begin
    Check('defined memcmp is exported by libc.so.6',
          ElfSoExportsSymbol(LIBC, 'memcmp'), True);
    Check('REFUSED memcmp is only IMPORTED by libSDL2 (SHN_UNDEF)',
          ElfSoExportsSymbol(SDL64, 'memcmp'), False);
  end
  else
    Skip('the SHN_UNDEF pair', 'needs ' + SDL64 + ' and ' + LIBC);

  { ===== PAIR 3: the ticket's counterexample, measured on both sides ======
    /usr/include/net/if.h is a glibc header; libnet is an unrelated
    packet-crafting library that occupies the name and IS installed here. The
    first row matters as much as the second: it says libnet is refused for
    ANSWERING NOTHING and not for being the wrong architecture, which is the
    only reading that makes it evidence about this feature. }
  if Present(LIBNET) and Present(LIBC) then
  begin
    LoadFile(LIBNET, body);
    Check('native  libnet.so.9 is a well-formed native ELF64',
          ElfIsNative64(body), True);
    Check('REFUSED ...and exports none of net/if.h: if_nametoindex',
          ElfSoExportsSymbol(LIBNET, 'if_nametoindex'), False);
    Check('REFUSED ...nor if_indextoname',
          ElfSoExportsSymbol(LIBNET, 'if_indextoname'), False);
    Check('defined ...while libc.so.6, where they really live, does',
          ElfSoExportsSymbol(LIBC, 'if_nametoindex'), True);
  end
  else
    Skip('the net/if.h counterexample',
         'needs libnet.so.9 INSTALLED (' + LIBNET + '); without it this row '
         + 'would pass by absence and certify nothing');

  { ===== Rows that build their own input, and so always run ================
    Without these an all-skipped run would print no failures and read green. }

  Check('REFUSED a path that does not exist',
        ElfSoExportsSymbol('/nonexistent/libnothing.so.0', 'main'), False);

  { A real file with real bytes that is not an ELF at all. /etc/ld.so.cache is
    the one this compiler already reads, so it is the honest near-miss. }
  if Present('/etc/ld.so.cache') then
  begin
    LoadFile('/etc/ld.so.cache', body);
    Check('REFUSED /etc/ld.so.cache is a real file and not an ELF',
          ElfIsNative64(body), False);
  end
  else
    Skip('the not-an-ELF row', '/etc/ld.so.cache absent');

  { TRUNCATED: a genuine ELF header whose section table is past EOF. This is
    the shape the bounds checks exist for, no distribution ships one, and a
    reader that trusted e_shoff would read off the end of the string here. }
  if Present(LIBC) then
  begin
    LoadFile(LIBC, body);
    tmp := GetTempDir + 'pxx_truncated_elf.so';
    Assign(fh, tmp); Rewrite(fh);
    for i := 1 to 200 do Write(fh, Byte(Ord(body[i])));
    Close(fh);
    LoadFile(tmp, body);
    Check('native  a 200-byte head of libc.so.6 still reads as ELFCLASS64',
          ElfIsNative64(body), True);
    Check('REFUSED ...and its section table is past EOF, so no symbol resolves',
          ElfSoExportsSymbol(tmp, 'memcmp'), False);
    Erase(fh);
  end
  else
    Skip('the truncated-ELF row', LIBC + ' absent');

  writeln;
  writeln('test_elfdynsym: ', Ran, ' checked, ', Skipped, ' skipped, ',
          Failures, ' failed');
  if Ran < 3 then
  begin
    writeln('test_elfdynsym: FAIL -- fewer than three rows actually ran, so a '
            + 'green result here would be certifying nothing');
    Halt(1);
  end;
  if Failures > 0 then Halt(1);
  writeln('test_elfdynsym: PASS');
end.
