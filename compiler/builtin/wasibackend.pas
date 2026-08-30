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
  intrinsic (pasparser_proc.inc, on the precedent of
  `if cWantsSoftFloat then ParseUsesUnitAmbient('softfloat')`). An ambient
  wasm-only unit would be parsed by every lane's next build, including by the
  older pinned compiler they are using, and a construct it could not read would
  break targets that have nothing to do with wasm.

  DUPLICATION, DELIBERATE AND TEMPORARY. The preopen/rights core below is
  copied from platform_backend.pas rather than shared, so that this commit
  changes no existing file's behaviour and check_wasi.sh keeps proving the PAL
  unchanged. Two copies of a CAPABILITY MODEL is exactly the kind that drifts
  silently — one path opening files the other refuses — so it does not stay:
  the next commit makes platform_backend delegate here and deletes its copy.
  If you are reading this comment and platform_backend still has its own
  preopen table, that follow-up did not happen and this is now a real defect. }

interface

function PXXWasiOpen(path: PChar; posixFlags, mode: Integer): Integer;
function PXXWasiRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PXXWasiWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PXXWasiClose(handle: Integer): Integer;
function PXXWasiFchmod(handle, mode: Integer): Integer;

implementation

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
  WasiScratch    : array[0..15] of Byte;     { prestat / nread / newoffset }
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

end.
