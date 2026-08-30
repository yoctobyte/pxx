unit wasibackend;

{ The WASI file core, as a BUILTIN unit rather than a PAL unit.

  Why this exists at all, since the same logic already lives in
  lib/rtl/platform/wasi/platform_backend.pas:

  `sysopen` / `sysread` / `syswrite` / `sysclose` are INTRINSICS. On every
  native target the backend emits a raw `syscall` instruction inline, which is
  exactly why compiler.pas needs no RTL and links no PAL — that is a design
  goal, not an accident. wasm has no syscall instruction, so the backend has to
  emit a CALL to something; and WASI's `path_open` is capability-based (a guest
  cannot open a path, only a path RELATIVE to a directory the host granted it),
  so that something is a few hundred lines of preopen bookkeeping rather than
  one instruction.

  The PAL is the wrong home for it: compiler.pas deliberately does not link the
  PAL, and linking it to get file I/O would trade the design goal for the
  feature. A builtin unit is the right home — the compiler already links
  builtin/ by necessity, which is where PXXAlloc and the string runtime live
  and what the backend already emits calls into.

  NOT AMBIENT. builtinheap is injected into every program on every target;
  this one is injected only when a wasm32 compilation actually uses a sys*
  intrinsic, or calls the LoadFile builtin (pasparser_prog.inc, on the
  precedent of
  `if cWantsSoftFloat then ParseUsesUnitAmbient('softfloat')`). An ambient
  wasm-only unit would be parsed by every lane's next build, including by the
  older pinned compiler they are using, and a construct it could not read would
  break targets that have nothing to do with wasm.

  DUPLICATION: DELIBERATE, AND PENDING A DECISION RATHER THAN OWED A CLEANUP.
  The preopen/rights core below is copied from platform_backend.pas rather than
  shared, so that its landing commit changed no existing file's behaviour and
  check_wasi.sh kept proving the PAL unchanged.

  THIS PARAGRAPH REPLACES A PROMISE, and how it was redeemed is worth keeping.
  It used to say the next commit would make platform_backend delegate here and
  delete its copy, and it ended: "If you are reading this comment and
  platform_backend still has its own preopen table, that follow-up did not
  happen and this is now a real defect." That follow-up did not happen and
  nobody had filed it — the sentence is the only thing in the tree that caught
  it, months of green checks later. It worked; it is replaced, not deleted,
  because a promise that has been overtaken by a decision must stop reading as
  an unpaid debt or the next reader re-files it.

  Where it actually stands: DECIDED, and the answer is keep both.
  decide-which-way-the-wasi-capability-model-should-point-once-it-has-one-owner
  resolved as C — two copies deliberately, drift guarded by a test, and do NOT
  invert the layering by pointing a lib/rtl unit at compiler/builtin. It follows
  from the owner's standing constraint that no PAL belongs in the compiler's
  sources, which is the same constraint that put this unit here in the first
  place. So TWO COPIES IS THE CURRENT INTENDED STATE — and the ticket has since
  been REOPENED on one specific ground: that the cost is paid per FIX rather
  than per divergence (see below), which is a quantity the differential test
  cannot reduce. So do not read "decided" as settled forever.

  What to do while reading this is unchanged either way: do not unify, and keep
  the two copies in step.

  WHAT GUARDS IT MEANWHILE, and what does not:

  * test/wasm/check_wasidiff.sh asks both models the same nine questions in ONE
    module — including the refusals, which are the half that matters — and
    fails if they answer differently. That covers DRIFT.
  * It does NOT cover a defect copied at birth. The copies are each other's only
    oracle there, so an identical bug makes them agree. Measured, not feared:
    the u64 out-param alignment defect
    (bug-wasm-hosted-compiler-segfaults-the-host-after-a-successful-parse) was
    in both, agreed on by both, and had to be fixed twice. check_align.sh
    catches that class by using a strict HOST instead of the other copy.

  So the demonstrated cost of this duplication is not divergence — it is that
  every fix must be applied twice and nothing tells the second person the second
  copy exists. If you are fixing something below, fix
  lib/rtl/platform/wasi/platform_backend.pas too. }

interface

function PXXWasiOpen(path: PChar; posixFlags, mode: Integer): Integer;
function PXXWasiRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PXXWasiWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PXXWasiClose(handle: Integer): Integer;
function PXXWasiFchmod(handle, mode: Integer): Integer;

{ LoadFile(path, dst) -- the pxx builtin, which every other target lowers to
  builtinheap's PXXStrLoadFile. That body is unreachable here: it is written
  over PXXSysOpenRO / PXXSysLseek / PXXSysRead / PXXSysClose, whose {$if} chain
  has no wasm arm and correctly answers -1 rather than inventing an fd. Giving
  it one would mean either a THIRD copy of the preopen model inside
  builtinheap, or making builtinheap `uses wasibackend` -- and the second is
  what forces every wasm32 program that merely allocates a string to import
  fd_prestat_get, which is the exact regression the on-demand injection exists
  to prevent. So the wasm arm of that one algorithm lives here instead, and the
  backend picks the callee by target. }
function PXXWasiLoadFile(path: Pointer): Pointer;

{ sysgetdents64(fd, buf, count) -- the Linux directory-read syscall that
  elfwriter.inc's PxxListDir walks. It is NOT one of the tkSys* intrinsics: it
  is an ordinary function over __pxxrawsyscall, which is IR op 54 and the one
  node wasm can never lower, there being no syscall instruction to lower it to.
  So the wasm arm of sysgetdents64 calls this instead. }
function PXXWasiGetDents(handle: Integer; buf: Pointer; len: Integer): Integer;

implementation

{ For PXXAlloc / PXXFree / PXXStrFromLit, used by PXXWasiLoadFile below. The
  dependency runs this way and only this way: builtinheap must not know about
  this unit (see PXXWasiLoadFile's note), and it is injected ahead of this one
  in pasparser_prog.inc, so naming it here adds no cycle and no ordering
  hazard. Every other entry point in this unit is free of it. }
uses builtinheap;

{ POSIX open(2) flag bits, as the sys* intrinsics pass them -- `sysopen(p, 577)`
  is O_WRONLY|O_CREAT|O_TRUNC. Redeclared here rather than imported: this unit
  must not depend on the RTL, which is the whole reason it is in builtin/. }
const
  O_ACCMODE   = 3;
  O_RDONLY    = 0;
  O_WRONLY    = 1;
  O_RDWR      = 2;
  O_CREAT     = $40;
  O_EXCL      = $80;
  O_TRUNC     = $200;
  O_APPEND    = $400;
  O_DIRECTORY = $10000;

  PAL_ERR_UNSUPPORTED = -38;   { Linux ENOSYS, the portable "not here" }

  { WASI preview1 `oflags` and `fdflags`. Small, closed sets — nothing like
    the open(2) flag space, because the capability model does the work the
    flags do on Unix. }
  WASI_O_CREAT     = 1;
  WASI_O_DIRECTORY = 2;
  WASI_O_EXCL      = 4;
  WASI_O_TRUNC     = 8;
  WASI_FD_APPEND   = 1;

  { Rights. An fd carries the rights it was OPENED with, and an operation the
    fd was not granted fails with ENOTCAPABLE (76) rather than EPERM — so
    these are not a formality, they are the difference between an fd that
    works and one that reads back nothing. Requesting the full mask is
    tempting and wrong on a strict host: a preopen that lacks a right refuses
    the open rather than intersecting. So each mode asks for what it will
    actually use. }
  WR_DATASYNC       = 1;
  WR_READ           = 2;
  WR_SEEK           = 4;
  WR_FDSTAT_SETFL   = 8;
  WR_SYNC           = 16;
  WR_TELL           = 32;
  WR_WRITE          = 64;
  WR_ADVISE         = 128;
  WR_ALLOCATE       = 256;
  WR_PATH_CREATE_DIR = 512;
  WR_PATH_CREATE_FILE = 1024;
  WR_PATH_OPEN      = 8192;
  WR_READDIR        = 16384;
  WR_PATH_RENAME_SRC = 65536;
  WR_PATH_RENAME_DST = 131072;
  WR_PATH_FILESTAT_GET = 262144;
  WR_FD_FILESTAT_GET = 2097152;
  WR_FD_FILESTAT_SETSZ = 4194304;
  WR_PATH_REMOVE_DIR = 33554432;
  WR_PATH_UNLINK    = 67108864;

  WASI_CLOCK_REALTIME = 0;
  WASI_CLOCK_MONOTONIC = 1;

  WASI_PREOPEN_MAX  = 8;

  WASI_PREOPEN_NAMEMAX = 128;

{$ifdef CPU_WASM32}
{ --- the WASI preview1 surface, declared rather than hardcoded -------------

  `external 'module' name 'field'` and a wasm import are the same declaration:
  the module/field pair a wasm import needs is exactly what the Pascal form
  already carries. That is what makes this a PAL backend rather than a set of
  backend special cases.

  Guarded by CPU_WASM32 because a NATIVE build of an external emits a
  DT_NEEDED for its library, and `wasi_snapshot_preview1` is not a shared
  object — the binary would link and then refuse to load. Every entry point
  below therefore has a non-wasm arm that refuses, so this unit still compiles
  (and honestly fails) if it is ever put on a native search path by mistake. }

function wasi_fd_read(fd: Integer; iovs: Pointer; iovsLen: Integer;
                      nread: Pointer): Integer;
  external 'wasi_snapshot_preview1' name 'fd_read';
function wasi_fd_write(fd: Integer; iovs: Pointer; iovsLen: Integer;
                       nwritten: Pointer): Integer;
  external 'wasi_snapshot_preview1' name 'fd_write';
function wasi_fd_seek(fd: Integer; offset: Int64; whence: Integer;
                      newoffset: Pointer): Integer;
  external 'wasi_snapshot_preview1' name 'fd_seek';
function wasi_fd_close(fd: Integer): Integer;
  external 'wasi_snapshot_preview1' name 'fd_close';
function wasi_fd_readdir(fd: Integer; buf: Pointer; bufLen: Integer;
                         cookie: Int64; bufused: Pointer): Integer;
  external 'wasi_snapshot_preview1' name 'fd_readdir';
function wasi_fd_sync(fd: Integer): Integer;
  external 'wasi_snapshot_preview1' name 'fd_sync';
function wasi_path_open(dirfd, dirflags: Integer; path: Pointer;
                        pathLen, oflags: Integer;
                        rightsBase, rightsInh: Int64;
                        fdflags: Integer; openedFd: Pointer): Integer;
  external 'wasi_snapshot_preview1' name 'path_open';
function wasi_path_unlink_file(dirfd: Integer; path: Pointer;
                               pathLen: Integer): Integer;
  external 'wasi_snapshot_preview1' name 'path_unlink_file';
function wasi_path_create_directory(dirfd: Integer; path: Pointer;
                                    pathLen: Integer): Integer;
  external 'wasi_snapshot_preview1' name 'path_create_directory';
function wasi_path_remove_directory(dirfd: Integer; path: Pointer;
                                    pathLen: Integer): Integer;
  external 'wasi_snapshot_preview1' name 'path_remove_directory';
function wasi_path_rename(oldFd: Integer; oldPath: Pointer; oldLen: Integer;
                          newFd: Integer; newPath: Pointer;
                          newLen: Integer): Integer;
  external 'wasi_snapshot_preview1' name 'path_rename';
function wasi_fd_prestat_get(fd: Integer; buf: Pointer): Integer;
  external 'wasi_snapshot_preview1' name 'fd_prestat_get';
function wasi_fd_prestat_dir_name(fd: Integer; path: Pointer;
                                  pathLen: Integer): Integer;
  external 'wasi_snapshot_preview1' name 'fd_prestat_dir_name';
function wasi_clock_time_get(clockId: Integer; precision: Int64;
                             timeOut: Pointer): Integer;
  external 'wasi_snapshot_preview1' name 'clock_time_get';
function wasi_random_get(buf: Pointer; len: Integer): Integer;
  external 'wasi_snapshot_preview1' name 'random_get';

var
  { The preopen table, scanned once on first use. A WASI program cannot open a
    path; it can only open a path RELATIVE to a directory the host granted it,
    and the grants arrive as descriptors 3, 4, ... each carrying a name. So
    "resolve this path" means "find which grant it falls under", which is
    bookkeeping posix never has to do because the kernel holds the root. }
  WasiPreScanned : Boolean = False;
  WasiPreCount   : Integer = 0;
  WasiPreFd      : array[0..WASI_PREOPEN_MAX - 1] of Integer;
  WasiPreLen     : array[0..WASI_PREOPEN_MAX - 1] of Integer;
  WasiPreName    : array[0..WASI_PREOPEN_MAX * WASI_PREOPEN_NAMEMAX - 1] of Byte;
  WasiIov        : array[0..1] of Integer;   { one iovec: [ptr, len] }
  WasiScratch    : array[0..15] of Byte;     { prestat / nread (u32: align 4) }
  { The 8-BYTE out-params get their OWN scratch, and the reason is a layout rule
    rather than a style preference. symtab.inc's TypeAlign aligns a global to its
    ELEMENT type, so `array[0..15] of Byte` is aligned to ONE -- it landed
    4-aligned in the compiler's own module by luck, not by rule. WASI declares
    fd_seek's `filesize` and clock_time_get's `timestamp` as u64 and a strict
    host ENFORCES the 8-byte alignment: wasmtime refuses with `Pointer not
    aligned to 8`, while node's WASI accepted the same pointer and took the
    process down with SIGSEGV further on. An Int64 global aligns to 8 by that
    same TypeAlign rule, so this declaration is the guarantee.
    bug-wasm-hosted-compiler-segfaults-the-host-after-a-successful-parse }
  WasiScratch64  : Int64;      { fd_seek newoffset / clock_time_get timestamp }
  { fd_readdir staging. The COOKIE is the whole reason there is state here:
    getdents64 is a resumable walk whose position the kernel keeps in the fd,
    and WASI moved that position into the caller. One slot, not a table,
    because PxxListDir -- the only caller in this tree -- opens a directory,
    walks it to exhaustion and closes it before opening another. The fd is
    stored alongside so that interleaving two walks RESETS rather than silently
    continuing one from the other's position. }
  WasiDirBuf     : array[0..4095] of Byte;
  WasiDirFd      : Integer;
  WasiDirCookie  : Int64;
{$endif}

{ WASI errno -> the negative Linux-ish value PAL callers compare against.
  The two numbering schemes are unrelated: WASI's is alphabetical, so its 2 is
  EACCES where Linux's 2 is ENOENT, and passing one through as the other turns
  "no such file" into "permission denied" on every miss. Only the codes a file
  API can actually produce are mapped; anything else becomes -5 (EIO), which
  is honest — "the host refused and we do not have a better name for it" —
  rather than a plausible wrong code. }
function WasiErr(e: Integer): Integer;
begin
  if e = 0 then begin WasiErr := 0; Exit; end;
  case e of
    2:  WasiErr := -13;   { EACCES }
    6:  WasiErr := -11;   { EAGAIN }
    8:  WasiErr := -9;    { EBADF }
    20: WasiErr := -17;   { EEXIST }
    21: WasiErr := -14;   { EFAULT }
    27: WasiErr := -4;    { EINTR }
    28: WasiErr := -22;   { EINVAL }
    29: WasiErr := -5;    { EIO }
    31: WasiErr := -21;   { EISDIR }
    32: WasiErr := -40;   { ELOOP }
    33: WasiErr := -24;   { EMFILE }
    37: WasiErr := -36;   { ENAMETOOLONG }
    44: WasiErr := -2;    { ENOENT }
    48: WasiErr := -12;   { ENOMEM }
    51: WasiErr := -28;   { ENOSPC }
    52: WasiErr := PAL_ERR_UNSUPPORTED;   { ENOSYS }
    54: WasiErr := -20;   { ENOTDIR }
    55: WasiErr := -39;   { ENOTEMPTY }
    58: WasiErr := PAL_ERR_UNSUPPORTED;   { ENOTSUP }
    63: WasiErr := -1;    { EPERM }
    64: WasiErr := -32;   { EPIPE }
    68: WasiErr := -34;   { ERANGE }
    69: WasiErr := -30;   { EROFS }
    70: WasiErr := -29;   { ESPIPE }
    75: WasiErr := -18;   { EXDEV }
    76: WasiErr := -1;    { ENOTCAPABLE -> EPERM: the fd exists and the
                            operation is refused, which is what EPERM says }
  else
    WasiErr := -5;
  end;
end;


{$ifdef CPU_WASM32}

{ --- path resolution against the preopen table ----------------------------

  This is the part of a WASI backend that has no posix counterpart at all.
  There is no `open(path)`: a program may only reach a directory the host
  PREOPENED for it, and every path call is `(dirfd, relative_path)`. The
  grants arrive as descriptors 3, 4, ... and `fd_prestat_dir_name` gives each
  one's name. Resolving `/tmp/x` means finding the grant it falls under and
  handing the host the remainder.

  Scanned ONCE and cached, because the set cannot change: preopens are fixed
  at instantiation and there is no call that adds one. }

function WasiStrLen(p: PChar): Integer;
var n: Integer;
begin
  n := 0;
  if p <> nil then
    while PByte(Int64(p) + n)^ <> 0 do n := n + 1;
  WasiStrLen := n;
end;

procedure WasiScanPreopens;
var fd, i, nameLen, rc: Integer;
begin
  if WasiPreScanned then Exit;
  WasiPreScanned := True;
  WasiPreCount := 0;
  fd := 3;
  { The scan STOPS at the first non-preopen rather than skipping it: preview1
    guarantees the grants are contiguous from 3, and a host that returned
    EBADF for one and a prestat for the next would be outside the spec. Reading
    on regardless would mean calling fd_prestat_get on ordinary descriptors the
    program later opens. }
  while (fd < 3 + WASI_PREOPEN_MAX) and (WasiPreCount < WASI_PREOPEN_MAX) do
  begin
    for i := 0 to 15 do WasiScratch[i] := 0;
    rc := wasi_fd_prestat_get(fd, @WasiScratch[0]);
    if rc <> 0 then Exit;
    { prestat: [tag: u8][pad*3][u32 name_len]. tag 0 = directory; there is no
      other tag in preview1, but an unknown one is skipped rather than
      guessed at. }
    if WasiScratch[0] <> 0 then
    begin
      fd := fd + 1;
      continue;
    end;
    nameLen := Integer(WasiScratch[4]) or (Integer(WasiScratch[5]) shl 8)
               or (Integer(WasiScratch[6]) shl 16)
               or (Integer(WasiScratch[7]) shl 24);
    if (nameLen <= 0) or (nameLen >= WASI_PREOPEN_NAMEMAX) then
    begin
      fd := fd + 1;
      continue;
    end;
    if wasi_fd_prestat_dir_name(fd,
          @WasiPreName[WasiPreCount * WASI_PREOPEN_NAMEMAX], nameLen) <> 0 then
    begin
      fd := fd + 1;
      continue;
    end;
    { A trailing slash on a grant name would make every prefix test off by one,
      and hosts differ on whether they include it. Normalised here, once. }
    while (nameLen > 1)
          and (WasiPreName[WasiPreCount * WASI_PREOPEN_NAMEMAX + nameLen - 1] = 47) do
      nameLen := nameLen - 1;
    WasiPreFd[WasiPreCount] := fd;
    WasiPreLen[WasiPreCount] := nameLen;
    WasiPreCount := WasiPreCount + 1;
    fd := fd + 1;
  end;
end;

{ Find the grant `path` falls under. Returns its descriptor and sets relOfs to
  the index in `path` where the host-relative remainder starts, or -1.

  The LONGEST match wins, so a program given both `/` and `/tmp` opens
  `/tmp/x` through the tighter grant — which is what the capability model is
  for, and also what avoids a host that refuses `..`-free traversal out of the
  broader one. }
function WasiFindPreopen(path: PChar; pathLen: Integer;
                         var relOfs: Integer): Integer;
var i, j, n, base: Integer; ok, absolute: Boolean; best, bestLen: Integer;
begin
  WasiScanPreopens;
  best := -1;
  bestLen := -1;
  relOfs := 0;
  absolute := (pathLen > 0) and (PByte(Int64(path))^ = 47);
  for i := 0 to WasiPreCount - 1 do
  begin
    n := WasiPreLen[i];
    base := i * WASI_PREOPEN_NAMEMAX;
    { A grant named "." is the program's working directory and matches any
      RELATIVE path with nothing stripped. It never matches an absolute one. }
    if (n = 1) and (WasiPreName[base] = 46) then
    begin
      if (not absolute) and (bestLen < 0) then
      begin
        best := WasiPreFd[i]; bestLen := 0; relOfs := 0;
      end;
      continue;
    end;
    if not absolute then continue;
    if pathLen < n then continue;
    ok := True;
    for j := 0 to n - 1 do
      if PByte(Int64(path) + j)^ <> WasiPreName[base + j] then
      begin
        ok := False;
        break;
      end;
    { The match must end on a component boundary: "/tmpfoo" is not under
      "/tmp". A grant of "/" is length 1 and its own separator, so it needs no
      boundary character after it. }
    if ok and (n > 1) and (pathLen > n) and (PByte(Int64(path) + n)^ <> 47) then
      ok := False;
    if ok and (n > bestLen) then
    begin
      best := WasiPreFd[i];
      bestLen := n;
      relOfs := n;
      { Skip the separator so the remainder is relative, which is the only
        thing path_open accepts. A path exactly equal to the grant leaves an
        empty remainder and is answered as "." below. }
      while (relOfs < pathLen) and (PByte(Int64(path) + relOfs)^ = 47) do
        relOfs := relOfs + 1;
    end;
  end;
  WasiFindPreopen := best;
end;

{$endif}

{ --- the five entry points the sys* intrinsics lower to --------------------- }

{ sysopen(path, flags[, mode]) -> fd, or a negative errno.

  Takes POSIX open(2) flags, because that is what the intrinsic's callers
  already pass (`sysopen(p, 577)` is O_WRONLY|O_CREAT|O_TRUNC), and translates
  them to WASI's much smaller oflags/fdflags pair plus a RIGHTS mask. The
  rights are not a formality: an fd carries what it was opened with, and an
  operation it was not granted fails ENOTCAPABLE rather than EPERM, so asking
  for too few gives an fd that opens and then fails on first use. Asking for
  the full mask is the other trap -- a strict host REFUSES an open whose
  requested rights exceed the preopen's, rather than intersecting them. }
function PXXWasiOpen(path: PChar; posixFlags, mode: Integer): Integer;
{$ifdef CPU_WASM32}
var dirfd, relOfs, pathLen, oflags, fdflags, acc, rc: Integer;
    rights: Int64;
{$endif}
begin
{$ifdef CPU_WASM32}
  pathLen := WasiStrLen(path);
  if pathLen = 0 then begin Result := -2; Exit; end;
  dirfd := WasiFindPreopen(path, pathLen, relOfs);
  if dirfd < 0 then begin Result := -2; Exit; end;

  oflags := 0;
  if (posixFlags and O_CREAT) <> 0 then oflags := oflags or WASI_O_CREAT;
  if (posixFlags and O_EXCL) <> 0 then oflags := oflags or WASI_O_EXCL;
  if (posixFlags and O_TRUNC) <> 0 then oflags := oflags or WASI_O_TRUNC;
  if (posixFlags and O_DIRECTORY) <> 0 then oflags := oflags or WASI_O_DIRECTORY;
  fdflags := 0;
  if (posixFlags and O_APPEND) <> 0 then fdflags := fdflags or WASI_FD_APPEND;

  acc := posixFlags and O_ACCMODE;
  rights := WR_SEEK or WR_TELL or WR_FD_FILESTAT_GET or WR_ADVISE;
  if (acc = O_RDONLY) or (acc = O_RDWR) then
    rights := rights or WR_READ or WR_READDIR;
  if (acc = O_WRONLY) or (acc = O_RDWR) then
    rights := rights or WR_WRITE or WR_SYNC or WR_DATASYNC
              or WR_ALLOCATE or WR_FD_FILESTAT_SETSZ or WR_FDSTAT_SETFL;

  WasiScratch[0] := 0; WasiScratch[1] := 0;
  WasiScratch[2] := 0; WasiScratch[3] := 0;
  { dirflags = 1 (SYMLINK_FOLLOW), matching openat's default. }
  if relOfs >= pathLen then
    rc := wasi_path_open(dirfd, 1, PChar(Int64(@WasiPreName[0])), 0,
                         oflags, rights, rights, fdflags, @WasiScratch[0])
  else
    rc := wasi_path_open(dirfd, 1, Pointer(Int64(path) + relOfs),
                         pathLen - relOfs,
                         oflags, rights, rights, fdflags, @WasiScratch[0]);
  if rc <> 0 then begin Result := WasiErr(rc); Exit; end;
  Result := Integer(WasiScratch[0]) or (Integer(WasiScratch[1]) shl 8)
            or (Integer(WasiScratch[2]) shl 16)
            or (Integer(WasiScratch[3]) shl 24);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

{ One iovec, not a scatter list: the intrinsic's contract is a single buffer.
  The byte count comes back through MEMORY rather than in the return value --
  every WASI call returns only an errno. }
function PXXWasiRead(handle: Integer; buf: Pointer; len: Integer): Int64;
{$ifdef CPU_WASM32}
var rc: Integer;
{$endif}
begin
{$ifdef CPU_WASM32}
  if len <= 0 then begin Result := 0; Exit; end;
  WasiIov[0] := Integer(buf);
  WasiIov[1] := len;
  WasiScratch[0] := 0; WasiScratch[1] := 0;
  WasiScratch[2] := 0; WasiScratch[3] := 0;
  rc := wasi_fd_read(handle, @WasiIov[0], 1, @WasiScratch[0]);
  if rc <> 0 then begin Result := WasiErr(rc); Exit; end;
  Result := Integer(WasiScratch[0]) or (Integer(WasiScratch[1]) shl 8)
            or (Integer(WasiScratch[2]) shl 16)
            or (Integer(WasiScratch[3]) shl 24);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PXXWasiWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
{$ifdef CPU_WASM32}
var rc: Integer;
{$endif}
begin
{$ifdef CPU_WASM32}
  if len <= 0 then begin Result := 0; Exit; end;
  WasiIov[0] := Integer(buf);
  WasiIov[1] := len;
  WasiScratch[0] := 0; WasiScratch[1] := 0;
  WasiScratch[2] := 0; WasiScratch[3] := 0;
  rc := wasi_fd_write(handle, @WasiIov[0], 1, @WasiScratch[0]);
  if rc <> 0 then begin Result := WasiErr(rc); Exit; end;
  Result := Integer(WasiScratch[0]) or (Integer(WasiScratch[1]) shl 8)
            or (Integer(WasiScratch[2]) shl 16)
            or (Integer(WasiScratch[3]) shl 24);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PXXWasiClose(handle: Integer): Integer;
begin
{$ifdef CPU_WASM32}
  Result := WasiErr(wasi_fd_close(handle));
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

{ chmod: SUCCEEDS AND DOES NOTHING, and that is a deliberate call rather than
  an oversight.

  WASI preview1 has no chmod at all -- there is no mode bit a guest can set,
  and the PAL correctly answers PAL_ERR_UNSUPPORTED for PalBackendFchmod. But
  the compiler's every output path is `sysopen / syswrite / sysfchmod(fd, 420)
  / sysclose` (asmtext_wasm.inc:161, asmdisasm_x64.inc:913), so refusing here
  would fail every write of an object file over a permission bit that does not
  exist on this platform.

  This is NOT the same as pretending an unsupported operation worked. On a
  system with no file modes, "set this file's mode" is VACUOUS rather than
  unimplemented -- there is no observable the caller could check and find
  wrong. The honest failure would be a host that HAS modes and ignores the
  request, which is not this one.

  If a caller ever needs to know, the distinction belongs in a capability
  query (PalBackendHasFiles' shape), not in an errno from a call whose whole
  meaning is absent. }
function PXXWasiFchmod(handle, mode: Integer): Integer;
begin
{$ifdef CPU_WASM32}
  Result := 0;
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

{ Read a whole file into a fresh managed string. Returns the handle (refcount 1,
  nul-terminated) or nil if the file cannot be opened -- the SAME contract as
  builtinheap's PXXStrLoadFile, because the pxx `LoadFile` builtin's callers
  test `Length(dst) = 0` and nothing else.

  Sized with fd_seek rather than fd_filestat_get: PXXWasiOpen already requests
  WR_SEEK for every mode, so this needs no change to the rights mask, and a
  right that is requested but never used is the one that silently stops being
  requested later.

  It reads into a staging block and then copies through PXXStrFromLit rather
  than allocating the managed header itself. That is one memcpy of the file, and
  it buys not having a second place in the tree that knows the layout of a
  managed string -- PXXHdrInit and the header offsets are builtinheap's
  business, and PXXStrFromLit is the interface it publishes for exactly this.

  A zero-length file is a real case (an empty include), and it must come back as
  an EMPTY STRING rather than nil: nil is how this reports "could not open", and
  the two are different answers to the caller. }
function PXXWasiLoadFile(path: Pointer): Pointer;
{$ifdef CPU_WASM32}
var fd: Integer; size, n: Int64; buf: Pointer;
{$endif}
begin
{$ifdef CPU_WASM32}
  Result := nil;
  if path = nil then Exit;
  fd := PXXWasiOpen(PChar(path), O_RDONLY, 0);
  if fd < 0 then Exit;

  size := 0;
  WasiScratch64 := 0;
  if wasi_fd_seek(fd, 0, 2, @WasiScratch64) = 0 then       { WHENCE_END }
    size := WasiScratch64;
  WasiScratch64 := 0;
  if wasi_fd_seek(fd, 0, 0, @WasiScratch64) <> 0 then      { WHENCE_SET }
    size := 0;

  if size <= 0 then
  begin
    { Opened but empty (or unseekable): an empty string, NOT nil. }
    PXXWasiClose(fd);
    Result := PXXStrFromLit(0, path);
    Exit;
  end;

  buf := PXXAlloc(size + 1, 8);
  n := PXXWasiRead(fd, buf, Integer(size));
  PXXWasiClose(fd);
  if n < 0 then n := 0;
  Result := PXXStrFromLit(n, buf);
  PXXFree(buf);
{$else}
  Result := nil;
{$endif}
end;

{ WASI's fd_readdir and Linux's getdents64 carry the SAME INFORMATION in two
  different records, so this is a translation, not a wrapper.

    WASI dirent -- 24 bytes, then the name, NOT nul-terminated:
      d_next:u64 @0   d_ino:u64 @8   d_namlen:u32 @16   d_type:u8 @20
    Linux dirent64, as PxxListDir reads it:
      d_ino:u64 @0    d_off:u64 @8   d_reclen:u16 @16   d_type:u8 @18
      d_name @19, NUL-TERMINATED

  d_ino and d_off are written as ZERO. The caller reads d_reclen and d_name and
  nothing else, and inventing plausible values for fields nobody reads is how a
  later reader comes to believe they mean something.

  The output record is never larger than the input that produced it -- 19+n+1
  rounded up to 8 is <= 24+n for every n -- so a staging buffer the size of the
  caller's cannot overflow it. The bound is checked anyway: that is an argument,
  not a guarantee.

  A TRUNCATED TAIL is normal rather than an error. fd_readdir fills the buffer
  and may cut the last entry's name; such an entry is dropped WITHOUT advancing
  the cookie, so the next call re-reads it whole. Advancing past it would lose a
  directory entry silently -- and a lost entry is exactly what makes
  ResolveCaseInsensitivePath answer "no such file" for a file that is there.

  Byte-at-a-time stores rather than PWord: PWord is a MACHINE word, four bytes
  on this target, so the 8-byte d_ino/d_off fields are not one store here even
  though they are on x86-64. }
function PXXWasiGetDents(handle: Integer; buf: Pointer; len: Integer): Integer;
{$ifdef CPU_WASM32}
var used, off, outOff, namlen, reclen, i, rc: Integer;
    nxt: Int64;
    dtype: Byte;
    dst: Int64;
{$endif}
begin
{$ifdef CPU_WASM32}
  Result := 0;
  if (buf = nil) or (len <= 0) then Exit;
  if handle <> WasiDirFd then
  begin
    WasiDirFd := handle;
    WasiDirCookie := 0;
  end;

  WasiScratch[0] := 0; WasiScratch[1] := 0;
  WasiScratch[2] := 0; WasiScratch[3] := 0;
  rc := wasi_fd_readdir(handle, @WasiDirBuf[0], 4096, WasiDirCookie,
                        @WasiScratch[0]);
  if rc <> 0 then begin Result := Integer(WasiErr(rc)); Exit; end;
  used := Integer(WasiScratch[0]) or (Integer(WasiScratch[1]) shl 8)
          or (Integer(WasiScratch[2]) shl 16)
          or (Integer(WasiScratch[3]) shl 24);
  if used > 4096 then used := 4096;

  dst := Int64(buf);
  outOff := 0;
  off := 0;
  while off + 24 <= used do
  begin
    nxt := Int64(WasiDirBuf[off]) or (Int64(WasiDirBuf[off + 1]) shl 8)
           or (Int64(WasiDirBuf[off + 2]) shl 16)
           or (Int64(WasiDirBuf[off + 3]) shl 24)
           or (Int64(WasiDirBuf[off + 4]) shl 32)
           or (Int64(WasiDirBuf[off + 5]) shl 40)
           or (Int64(WasiDirBuf[off + 6]) shl 48)
           or (Int64(WasiDirBuf[off + 7]) shl 56);
    namlen := Integer(WasiDirBuf[off + 16])
              or (Integer(WasiDirBuf[off + 17]) shl 8)
              or (Integer(WasiDirBuf[off + 18]) shl 16)
              or (Integer(WasiDirBuf[off + 19]) shl 24);
    dtype := WasiDirBuf[off + 20];
    if (namlen < 0) or (off + 24 + namlen > used) then Break;   { truncated }

    reclen := (19 + namlen + 1 + 7) and (not 7);
    if outOff + reclen > len then Break;

    for i := 0 to 17 do PByte(dst + outOff + i)^ := 0;   { d_ino, d_off }
    PByte(dst + outOff + 16)^ := Byte(reclen and $FF);
    PByte(dst + outOff + 17)^ := Byte((reclen shr 8) and $FF);
    PByte(dst + outOff + 18)^ := dtype;
    for i := 0 to namlen - 1 do
      PByte(dst + outOff + 19 + i)^ := WasiDirBuf[off + 24 + i];
    PByte(dst + outOff + 19 + namlen)^ := 0;

    WasiDirCookie := nxt;
    outOff := outOff + reclen;
    off := off + 24 + namlen;
  end;
  Result := outOff;
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

end.
