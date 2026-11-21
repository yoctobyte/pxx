{ SPDX-License-Identifier: Zlib }
unit palhostthread;
{ pxx's per-thread block for a thread pxx did NOT clone: one the host libc's
  pthread_create made. Two users:

  * palthread's PxxPthreadStart (the pthread route a pxx thread takes when
    the program links libc), through PxxThreadBlockInstall;
  * a C program built with --system-libs, whose own pthread_create the
    compiler predefines to __pxx_host_pthread_create (CHostPthreadRoute).

  Its own unit, not palthread's, because palthread compiles __pxxclone and so
  needs --threadsafe; a C program that takes the host's threads does not.
  x86-64 (gs) and i386 (fs) install a block; on every other target there is
  no second thread register and the install is a no-op.
  bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there }

interface

{ Make, fill and install the CALLING thread's own block. Returns it (0 when
  nothing was installed); tlsBytes + altBytes is what to munmap at the end.
  Must run before anything that reaches through the thread register: see
  PxxPthreadStart's header in palthread for the ordering rule. }
function PxxThreadBlockInstall(var tlsBytes, altBytes: Int64): Int64;

{ A C program's pthread_create under --system-libs (the compiler predefines the
  name to this): the host libc's pthread_create, with pxx's per-thread block
  installed in the new thread before its start routine runs. }
function __pxx_host_pthread_create(th, attr, start, arg: Pointer): Integer; cdecl;

{ C11 thrd_create under --system-libs, predefined to this the same way: glibc's
  own thrd_create calls its internal pthread_create, which no rename reaches,
  so it is replaced whole. The thread starts through the same block install;
  its int result rides in the pthread result, which is how glibc's thrd_join
  reads it. Returns thrd_success 0, thrd_busy 1, thrd_error 2, thrd_nomem 3
  (glibc's values). }
function __pxx_host_thrd_create(thr, func, arg: Pointer): Integer; cdecl;

{ The host libc's two, WEAK: nil unless the program links libc for another
  reason, so neither puts libc in a libc-free program's DT_NEEDED. palthread's
  pthread route uses them too; they are declared once, here.
  pthread_t is an unsigned long: pointer-sized. An Int64 here passed two words
  on a 32-bit target, and pthread_join then read the high half as `retval`. }
function c_pthread_create(th: Pointer; attr: Pointer; start: Pointer; arg: Pointer): Integer; cdecl;
  weakexternal 'libc.so.6' name 'pthread_create';
function c_pthread_join(th: PtrUInt; retval: Pointer): Integer; cdecl;
  weakexternal 'libc.so.6' name 'pthread_join';

implementation

{ Same rule as palthread's MmapOk: failure is [-4095,-1] or 0, never the sign. }
function HtMmapOk(r: Int64): Boolean;
begin
  HtMmapOk := not ((r = 0) or ((r < 0) and (r >= -4095)));
end;

const
  PROT_RW = 3;
  MAP_ANON_PRIV = $22;      { only x86-64/i386 reach these: see palthread }
{$ifdef PXX_OS_OPENBSD}
  MAP_STACK_PRIV = $20022;
{$else}
  MAP_STACK_PRIV = $22;
{$endif}
{$ifdef CPUX86_64}
  SYS_mmap        = 9;
  SYS_munmap      = 11;
  SYS_arch_prctl  = 158;
  SYS_sigaltstack = 131;
  ARCH_SET_GS     = $1001;
  ARCH_GET_FS     = $1003;
{$else}
{$ifdef CPUI386}
  SYS_mmap     = 192;
  SYS_munmap   = 91;
  SYS_set_thread_area = 243;
{$else}
  SYS_mmap     = -1;
  SYS_munmap   = -1;
{$endif}
{$endif}

function PxxThreadBlockInstall(var tlsBytes, altBytes: Int64): Int64;
var
  blk, ignore, img, k: Int64;
  ss: array[0..2] of Int64;
  desc: array[0..3] of LongWord;               { i386's struct user_desc }
begin
  blk := 0;
  tlsBytes := 0;
  altBytes := 0;
{$ifdef CPUX86_64}
  { x86-64: pxx's block lives on gs, which glibc does not use. i386 has its
    own arm below (fs). On aarch64 and arm32 the one thread register is
    glibc's in the dynamic binary this route implies, so there is nothing of
    pxx's to install (see the note at the weak imports). }
  tlsBytes := __pxxTlsBlockSize;
  altBytes := __pxxSigAltStackSize;
  { The CREATOR's init-image pointer, read while gs is still the creator's
    block. A raw pointer read, which the ordering rule above allows. The copy
    below starts this block's thread-locals at their initial values rather than
    at 0 (TLS_SLOT_INIT_IMAGE in the compiler). }
  img := 0;
{$ifdef PXX_HAS_TLS_INIT_IMAGE}
  if __pxxTlsUserBytes > 0 then
    img := PInt64(PtrUInt(__pxxTlsBase) + __pxxTlsInitImageSlotOff)^;
{$endif}
  blk := __pxxrawsyscall(SYS_mmap, 0, tlsBytes + altBytes,
                         PROT_RW, MAP_STACK_PRIV, -1, 0);
  if HtMmapOk(blk) then
  begin
    PInt64(blk)^ := blk;                       { slot 0 = the block's own address }
{$ifdef PXX_HAS_TLS_INIT_IMAGE}
    if img <> 0 then
    begin
      k := 0;
      while k < __pxxTlsUserBytes do
      begin
        PInt64(blk + __pxxTlsUserOff + k)^ := PInt64(img + k)^;
        k := k + 8;
      end;
      PInt64(blk + __pxxTlsInitImageSlotOff)^ := img;
    end;
{$endif}
    ignore := __pxxrawsyscall(SYS_arch_prctl, ARCH_SET_GS, blk, 0, 0, 0, 0);
{$ifdef PXX_HAS_TLS_OWNER_FS}
    { The owner marker (TLS_SLOT_OWNER_FS in the compiler): this thread's fs
      base, so a thread IT later creates through libc, which inherits this gs,
      is recognised as foreign at its first `try`. }
    ignore := __pxxrawsyscall(SYS_arch_prctl, ARCH_GET_FS, blk + __pxxTlsOwnerFsSlotOff, 0, 0, 0, 0);
{$endif}
    ss[0] := blk + tlsBytes;                   { ss_sp }
    ss[1] := 0;                                { ss_flags }
    ss[2] := altBytes;                         { ss_size }
    ignore := __pxxrawsyscall(SYS_sigaltstack, Int64(@ss[0]), 0, 0, 0, 0, 0);
  end;
{$endif}
{$ifdef CPUI386}
{$ifdef PXX_HAS_TLS_FS_ENTRY}
  { i386: pxx's block lives on fs, which glibc (on gs) does not use. This
    thread starts with the CREATOR's fs selector and a copy of its GDT TLS
    entries, so fs still reaches the creator's block: read the entry number
    and the init image through it, then point that same entry at a block of
    this thread's own. set_thread_area on the entry fs already selects makes
    the kernel reload fs. No alt stack: the i386 clone leg registers none
    either. The ordering rule above applies unchanged. }
  tlsBytes := __pxxTlsBlockSize;
  img := 0;
  if __pxxTlsUserBytes > 0 then
    img := PInt64(PtrUInt(__pxxTlsBase) + __pxxTlsInitImageSlotOff)^;
  k := PInt64(PtrUInt(__pxxTlsBase) + __pxxTlsFsEntrySlotOff)^;
  blk := __pxxrawsyscall(SYS_mmap, 0, tlsBytes, PROT_RW, MAP_ANON_PRIV, -1, 0);
  if HtMmapOk(blk) then
  begin
    PInt64(blk)^ := blk;                       { slot 0 = the block's own address }
    PInt64(blk + __pxxTlsFsEntrySlotOff)^ := k;
    if img <> 0 then
    begin
      ss[0] := 0;
      while ss[0] < __pxxTlsUserBytes do
      begin
        PInt64(blk + __pxxTlsUserOff + ss[0])^ := PInt64(img + ss[0])^;
        ss[0] := ss[0] + 8;
      end;
      PInt64(blk + __pxxTlsInitImageSlotOff)^ := img;
    end;
    desc[0] := LongWord(k);                    { entry_number }
    desc[1] := LongWord(blk);                  { base_addr }
    desc[2] := $FFFFF;                         { limit, in pages }
    desc[3] := $51;                            { seg_32bit | limit_in_pages | useable }
    ignore := __pxxrawsyscall(SYS_set_thread_area, Int64(PtrUInt(@desc[0])), 0, 0, 0, 0, 0);
    { Reload fs. Linux already did, for a selector naming the entry it just
      changed; qemu-user did not, and every pthread-made thread ran on its
      creator's block until this line existed. }
    ignore := Int64(PtrUInt(__pxxTlsFsReload));
  end;
{$endif}
{$endif}
  Result := blk;
end;

{$ifdef CPUX86_64}{$define PXX_HOST_THREAD_ROUTE}{$endif}
{$ifdef CPUI386}{$define PXX_HOST_THREAD_ROUTE}{$endif}

{$ifdef PXX_HOST_THREAD_ROUTE}
{ THE C PROGRAM'S OWN pthread_create, under --system-libs. Such a program
  calls the host libc's pthread_create directly, and glibc's thread starts on
  its creator's gs, so every `__thread` (and crtl's thread-local errno) was the
  creator's: `__thread int tl = 7` set to 9 in the thread read 9 in main, where
  gcc keeps 7. The compiler predefines `pthread_create` as
  __pxx_host_pthread_create for such a program (cpreproc.inc), so the host
  header's prototype and every call bind here; the real pthread_create then
  runs PxxHostCThreadStart, which installs a block of the thread's own before
  the C start routine runs and hands its return value back to pthread_join.

  Two leaks, both bounded by the thread count and both what the Pascal route
  above does too: a thread that leaves by pthread_exit (or is cancelled) skips
  the munmap; and the block is unmapped when the start routine RETURNS, so a
  pthread_key destructor written in pxx C that touches a thread-local after
  that runs on no block. """ + TK + """ }
type
  TPxxCStart = function(arg: Pointer): Pointer; cdecl;
  TPxxCStartRec = record
    Fn: TPxxCStart;
    Arg: Pointer;
  end;
  PPxxCStartRec = ^TPxxCStartRec;

function PxxHostCThreadStart(a: Pointer): Pointer; cdecl;
var
  blk, ignore, tlsBytes, altBytes: Int64;
  rec: PPxxCStartRec;
  fn: TPxxCStart;
  arg: Pointer;
begin
  { First, before anything that reaches through gs: the record is read and
    freed only once the thread's own block is in. }
  blk := PxxThreadBlockInstall(tlsBytes, altBytes);
  rec := PPxxCStartRec(a);
  fn := rec^.Fn;
  arg := rec^.Arg;
  FreeMem(rec);
  Result := fn(arg);
  if blk > 0 then
    ignore := __pxxrawsyscall(SYS_munmap, blk, tlsBytes + altBytes, 0, 0, 0, 0);
end;

function __pxx_host_pthread_create(th, attr, start, arg: Pointer): Integer; cdecl;
var rec: PPxxCStartRec;
begin
  if @c_pthread_create = nil then begin Result := 38; Exit; end;   { ENOSYS: no libc }
  rec := PPxxCStartRec(GetMem(SizeOf(TPxxCStartRec)));
  rec^.Fn := TPxxCStart(start);
  rec^.Arg := arg;
  Result := c_pthread_create(th, attr, @PxxHostCThreadStart, rec);
  if Result <> 0 then FreeMem(rec);
end;

type
  TPxxCThrdStart = function(arg: Pointer): Integer; cdecl;

function PxxHostCThrdStart(a: Pointer): Pointer; cdecl;
var
  blk, ignore, tlsBytes, altBytes: Int64;
  rec: PPxxCStartRec;
  fn: TPxxCThrdStart;
  arg: Pointer;
begin
  blk := PxxThreadBlockInstall(tlsBytes, altBytes);
  rec := PPxxCStartRec(a);
  fn := TPxxCThrdStart(rec^.Fn);
  arg := rec^.Arg;
  FreeMem(rec);
  Result := Pointer(PtrInt(fn(arg)));
  if blk > 0 then
    ignore := __pxxrawsyscall(SYS_munmap, blk, tlsBytes + altBytes, 0, 0, 0, 0);
end;

function __pxx_host_thrd_create(thr, func, arg: Pointer): Integer; cdecl;
var rec: PPxxCStartRec; e: Integer;
begin
  if @c_pthread_create = nil then begin Result := 2; Exit; end;   { thrd_error: no libc }
  rec := PPxxCStartRec(GetMem(SizeOf(TPxxCStartRec)));
  if rec = nil then begin Result := 3; Exit; end;
  rec^.Fn := TPxxCStart(func);
  rec^.Arg := arg;
  e := c_pthread_create(thr, nil, @PxxHostCThrdStart, rec);
  if e <> 0 then FreeMem(rec);
  if e = 0 then Result := 0
  else if e = 12 then Result := 3      { ENOMEM: thrd_nomem }
  else if e = 16 then Result := 1      { EBUSY: thrd_busy }
  else Result := 2;                    { thrd_error }
end;
{$else}
function __pxx_host_pthread_create(th, attr, start, arg: Pointer): Integer; cdecl;
begin
  Result := 38;   { ENOSYS: never predefined for a target without the route }
end;

function __pxx_host_thrd_create(thr, func, arg: Pointer): Integer; cdecl;
begin
  Result := 2;    { thrd_error: never predefined for a target without the route }
end;
{$endif}

end.
