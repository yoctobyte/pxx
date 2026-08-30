{ SPDX-License-Identifier: Zlib }
unit platform_backend;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ WASI PAL backend, selected by -Fulib/rtl/platform/wasi.

  WHY A THIRD BACKEND RATHER THAN AN ARM OF THE POSIX ONE. The posix backend
  reaches the kernel through `__pxxrawsyscall` and a per-architecture table of
  Linux syscall NUMBERS. wasm has no syscall instruction and no number space:
  a host call is an IMPORT, named by module and field, resolved at
  instantiation. There is nothing to add a `{$ifdef CPU_WASM32}` block to —
  the mechanism differs, not the constants. Before this file existed, every
  program that touched a file failed at PARSE time with `undefined variable
  (SYS_openat)`, because posix is the compiled-in default PAL and wasm32 fell
  into it.

  The seam is the one ESP already proved: `platform.pas` says `uses
  platform_backend`, and whichever backend directory is on the unit search
  path supplies it. So this needs no compiler change — pass
  `-Fulib/rtl/platform/wasi` and wasm32 binds here instead.

  WASI IS NOT A UNIX, and the shape of the gap is different from ESP's. ESP
  has no processes, so fork/exec/wait/kill are refused there. WASI preview1
  additionally has:

    * no process creation at all (same refusals as ESP, for a different
      reason: the ABI simply has no such call);
    * no sockets in preview1 proper (sock_accept exists, sock_send/sock_recv
      operate on already-open descriptors a host handed in; there is no
      socket(), no connect(), no bind());
    * CAPABILITY-BASED paths. There is no `open(path)`. A program may only
      reach directories the host PREOPENED for it, and every path operation is
      relative to one of those descriptors — `path_open(dirfd, ..., path)`.
      Resolving an absolute path means finding which preopen it falls under,
      which is bookkeeping this backend does and posix never has to;
    * no getuid/getgid/chmod/chown — the model has no users;
    * no mmap. Linear memory grows with `memory.grow` and nothing else.

  A refusal here returns PAL_ERR_UNSUPPORTED, exactly as ESP's does: a
  POSIX-shaped program meets a clear error rather than a wrong answer. That
  failure mode is deliberate and is the whole reason to write the refusals out
  rather than let the unit fail to compile. }

interface

uses platform_types;

function PalBackendPlatform: Integer;
function PalBackendHasFiles: Boolean;
function PalBackendHasSockets: Boolean;
function PalBackendHasThreads: Boolean;
function PalBackendHasDynlib: Boolean;
function PalBackendDlOpen(name: PChar): Pointer;
function PalBackendDlSym(handle: Pointer; sym: PChar): Pointer;
function PalBackendDlClose(handle: Pointer): Integer;
function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
function PalBackendFlush(handle: Integer): Integer;
function PalBackendClose(handle: Integer): Integer;
function PalBackendIgnoreSignal(sig: Integer): Integer;
function PalBackendDelete(path: PChar): Integer;
function PalBackendRename(oldPath, newPath: PChar): Integer;
function PalBackendMkdir(path: PChar; mode: Integer): Integer;
function PalBackendRmdir(path: PChar): Integer;
function PalBackendChdir(path: PChar): Integer;
function PalBackendSymlink(target, linkpath: PChar): Integer;
function PalBackendLink(oldPath, newPath: PChar): Integer;
function PalBackendGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendStat(path: PChar; var info: TPalFileStat): Integer;
function PalBackendStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
function PalBackendFstat(handle: Integer; var info: TPalFileStat): Integer;
function PalBackendLstat(path: PChar; var info: TPalFileStat): Integer;
function PalBackendFcntl(handle, cmd: Integer; arg: Int64): Integer;
function PalBackendFsync(handle: Integer): Integer;
function PalBackendFchmod(handle, mode: Integer): Integer;
function PalBackendChmod(path: PChar; mode: Integer): Integer;
function PalBackendUmask(mask: Integer): Integer;
function PalBackendFtruncate(handle: Integer; length: Int64): Integer;
function PalBackendAccess(path: PChar; mode: Integer): Integer;
function PalBackendFchown(handle, owner, group: Integer): Integer;
function PalBackendGeteuid: Integer;
function PalBackendGetuid: Integer;
function PalBackendGetgid: Integer;
function PalBackendGetegid: Integer;
function PalBackendGetppid: Integer;
function PalBackendReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
function PalBackendGetpid: Integer;
function PalBackendGetcwd(buf: PChar; size: Integer): Integer;
function PalBackendNanosleep(sec, nsec: Int64): Integer;
function PalBackendRealtime(var sec, nsec: Int64): Integer;
function PalBackendUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
function PalBackendMmapAnon(len: Int64): Pointer;
function PalBackendMmapAnonProt(len: Int64; prot: Integer): Pointer;
function PalBackendMprotect(addr: Pointer; len: Int64; prot: Integer): Integer;
function PalBackendMunmap(addr: Pointer; len: Int64): Integer;
function PalBackendSocket(domain, kind, proto: Integer): Integer;
function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
function PalBackendSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendConnectUnix(handle: Integer; const path: string): Integer;
function PalBackendBindIpv6(handle: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Integer;
function PalBackendConnectIpv6(handle: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Integer;
function PalBackendListen(handle, backlog: Integer): Integer;
function PalBackendAccept(handle: Integer): Integer;
function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendShutdown(handle, how: Integer): Integer;
function PalBackendSocketClose(handle: Integer): Integer;
function PalBackendSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
function PalBackendRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
function PalBackendSendToIpv6(handle: Integer; buf: Pointer; len: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Int64;
function PalBackendRecvFromIpv6(handle: Integer; buf: Pointer; len: Integer; var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Int64;
function PalBackendPoll(handle, events, timeoutMs: Integer): Integer;
function PalBackendPollSet(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
function PalBackendGetSockError(handle: Integer): Integer;
function PalBackendGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalBackendGetPeerNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalBackendGetSockOpt(handle, level, optname: Integer; valPtr: Pointer; lenPtr: Pointer): Integer;
function PalBackendIoctl(handle: Integer; cmd: NativeInt; argp: Pointer): Integer;
function PalBackendAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalBackendAcceptIpv6(handle: Integer; var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Integer;
function PalBackendMonotonicMillis: Int64;
procedure PalBackendYield;
function PalBackendVfork: Integer;
function PalBackendExecve(path: PChar; argv, envp: Pointer): Integer;
function PalBackendPipe2(var pipefd: array of Integer; flags: Integer): Integer;
function PalBackendDup2(oldFd, newFd: Integer): Integer;
function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
function PalBackendKill(pid, sig: Integer): Integer;
function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;

implementation

{ Redeclared rather than imported: platform.pas `uses` this unit, so this unit
  cannot `uses` platform.pas. Same duplication the ESP backend carries, for the
  same reason. }
const
  PAL_ERR_UNSUPPORTED = -38;   { Linux ENOSYS, the portable "not here" }

  PAL_OPEN_READ   = 0;
  PAL_OPEN_WRITE  = 1;
  PAL_OPEN_RDWR   = 2;
  PAL_OPEN_CREATE = $40;
  PAL_OPEN_EXCL   = $80;
  PAL_OPEN_TRUNC  = $200;
  PAL_OPEN_APPEND = $400;
  PAL_OPEN_DIRECTORY = $10000;

  PAL_PLATFORM_WASI = 3;

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

{ THERE IS A SECOND COPY OF EVERYTHING BELOW, and it is intended, not stale.
  compiler/builtin/wasibackend.pas holds the same preopen table, the same rights
  masks and the same path resolution, because compiler.pas links no PAL by
  design -- that is what
  decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal
  settled. The layering question (a shared home, and what may depend on what) is
  decide-which-way-the-wasi-capability-model-should-point-once-it-has-one-owner,
  and it resolved as: keep both copies, guard the drift with a test, and do not
  invert the layering by pointing this unit at compiler/builtin. It has since
  been REOPENED on the ground that the cost is paid per FIX rather than per
  divergence, so two copies is the CURRENT intended state rather than a settled
  one. Either way, do not unify it yourself.

  SO: A FIX HERE PROBABLY BELONGS THERE TOO. That is the duplication's real
  cost, and it is not the one people expect -- test/wasm/check_wasidiff.sh
  already catches DRIFT (it asks both models the same nine paths, refusals
  included, in one module), but nothing can catch a defect copied at BIRTH,
  because there the two copies agree with each other. That is not hypothetical:
  the u64 out-param alignment bug just below was in both and had to be fixed
  twice. Nothing but this comment tells you the other copy exists.
  bug-a-two-copies-of-the-wasi-capability-model-one-in-the-pal-one-in-wasibackend }

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
    4-aligned by luck, not by rule. WASI declares fd_seek's `filesize` and
    clock_time_get's `timestamp` as u64 and a strict host ENFORCES the 8-byte
    alignment: wasmtime refuses with `Pointer not aligned to 8`, while node's
    WASI accepted the same pointer and took the process down with SIGSEGV
    further on. An Int64 global aligns to 8 by that same TypeAlign rule, so this
    declaration is the guarantee.
    bug-wasm-hosted-compiler-segfaults-the-host-after-a-successful-parse }
  WasiScratch64  : Int64;      { fd_seek newoffset / clock_time_get timestamp }
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

function PalBackendPlatform: Integer;
begin
{$ifdef CPU_WASM32}
  { A third platform id, not posix's. A caller that branches on this must not
    be told "posix" by a backend with no fork, no sockets, no users and no
    absolute paths — the whole point of the value is to let a program ask. }
  Result := PAL_PLATFORM_WASI;
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendHasFiles: Boolean;
begin
{$ifdef CPU_WASM32}
  { True only when the host actually granted a directory. WASI without a
    preopen can open nothing at all, and a program that asks this
    question is asking whether it may try. }
  WasiScanPreopens;
  Result := WasiPreCount > 0;
{$else}
  Result := False;
{$endif}
end;

function PalBackendHasSockets: Boolean;
begin
  { preview1 has sock_send/sock_recv/sock_shutdown for descriptors a host
    handed in, and no socket(), connect() or bind(). There is no way for a
    program to CREATE one, which is what this question means. }
  Result := False;
end;

function PalBackendHasThreads: Boolean;
begin
  { A preview1 module has exactly one thread of execution. The threads
    proposal changes this and changes IR_ATOMIC's lowering with it —
    devdocs/dev/threading-model.md section 8. }
  Result := False;
end;

function PalBackendHasDynlib: Boolean;
begin
  { No dlopen: a module's imports are resolved once, at instantiation. }
  Result := False;
end;

function PalBackendDlOpen(name: PChar): Pointer;
begin
  Result := nil;
end;

function PalBackendDlSym(handle: Pointer; sym: PChar): Pointer;
begin
  Result := nil;
end;

function PalBackendDlClose(handle: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ There is no open(2) here. A WASI program may only open a path RELATIVE to a
  directory the host granted it, so this resolves `path` against the preopen
  table first and hands the host `(dirfd, remainder)`. A path under no grant is
  ENOENT, not EPERM: in the namespace this program was given it genuinely does
  not exist, and EPERM would suggest a permission that could be raised. }
function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
{$ifdef CPU_WASM32}
var dirfd, relOfs, pathLen, oflags, fdflags, acc, rc: Integer;
    rights: Int64;
{$endif}
begin
{$ifdef CPU_WASM32}
  pathLen := WasiStrLen(path);
  if pathLen = 0 then begin Result := -2; Exit; end;
  dirfd := WasiFindPreopen(path, pathLen, relOfs);
  if dirfd < 0 then
  begin
    Result := -2;
    Exit;
  end;

  oflags := 0;
  if (flags and PAL_OPEN_CREATE) <> 0 then oflags := oflags or WASI_O_CREAT;
  if (flags and PAL_OPEN_EXCL) <> 0 then oflags := oflags or WASI_O_EXCL;
  if (flags and PAL_OPEN_TRUNC) <> 0 then oflags := oflags or WASI_O_TRUNC;
  if (flags and PAL_OPEN_DIRECTORY) <> 0 then oflags := oflags or WASI_O_DIRECTORY;
  fdflags := 0;
  if (flags and PAL_OPEN_APPEND) <> 0 then fdflags := fdflags or WASI_FD_APPEND;

  { Rights, per mode. Asking for the full mask is the obvious shortcut and is
    wrong on a host that refuses rather than intersects; asking for too few
    gives an fd that opens and then fails ENOTCAPABLE on its first use. }
  acc := flags and 3;
  rights := WR_SEEK or WR_TELL or WR_FD_FILESTAT_GET or WR_ADVISE;
  if (acc = PAL_OPEN_READ) or (acc = PAL_OPEN_RDWR) then
    rights := rights or WR_READ or WR_READDIR;
  if (acc = PAL_OPEN_WRITE) or (acc = PAL_OPEN_RDWR) then
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
  if rc <> 0 then
  begin
    Result := WasiErr(rc);
    Exit;
  end;
  Result := Integer(WasiScratch[0]) or (Integer(WasiScratch[1]) shl 8)
            or (Integer(WasiScratch[2]) shl 16)
            or (Integer(WasiScratch[3]) shl 24);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

{ One iovec, not a scatter list: the PAL's contract is a single buffer, and
  building an iovec array here would be inventing a capability no caller asks
  for. The byte count comes back through memory rather than in the return
  value — every WASI call returns only an errno. }
function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
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

function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
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

{ whence is passed through unchanged: WASI's SET/CUR/END are 0/1/2, the same
  numbering lseek(2) uses, so a translation table here would be three identity
  rows. The new offset is 64-bit and arrives in memory little-endian. }
function PalBackendSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
{$ifdef CPU_WASM32}
var rc, i: Integer; v: Int64;
{$endif}
begin
{$ifdef CPU_WASM32}
  WasiScratch64 := 0;
  rc := wasi_fd_seek(handle, offset, whence, @WasiScratch64);
  if rc <> 0 then begin Result := WasiErr(rc); Exit; end;
  v := WasiScratch64;
  Result := v;
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendFlush(handle: Integer): Integer;
begin
{$ifdef CPU_WASM32}
  { The PAL's Flush is "make sure the bytes reached the host", which for an
    unbuffered descriptor is exactly fd_sync. There is no userspace buffer at
    this layer to drain first. }
  Result := WasiErr(wasi_fd_sync(handle));
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendClose(handle: Integer): Integer;
begin
{$ifdef CPU_WASM32}
  Result := WasiErr(wasi_fd_close(handle));
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendIgnoreSignal(sig: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ The three single-path operations share one shape: resolve against the
  preopen table, then call the host with (dirfd, remainder). Written out three
  times rather than through a helper taking a function pointer, because an
  indirect call through the PAL is a shape the ESP and posix backends do not
  have either, and the duplication here is six lines. }
function PalBackendDelete(path: PChar): Integer;
{$ifdef CPU_WASM32}
var dirfd, relOfs, pathLen: Integer;
{$endif}
begin
{$ifdef CPU_WASM32}
  pathLen := WasiStrLen(path);
  if pathLen = 0 then begin Result := -2; Exit; end;
  dirfd := WasiFindPreopen(path, pathLen, relOfs);
  if (dirfd < 0) or (relOfs >= pathLen) then begin Result := -2; Exit; end;
  Result := WasiErr(wasi_path_unlink_file(dirfd, Pointer(Int64(path) + relOfs),
                       pathLen - relOfs));
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

{ Rename resolves BOTH paths, and they may land under different grants — the
  host decides whether it can rename across them and answers EXDEV if not. That
  is its call to make, not this layer's. }
function PalBackendRename(oldPath, newPath: PChar): Integer;
{$ifdef CPU_WASM32}
var oldFd, newFd, oldRel, newRel, oldLen, newLen: Integer;
{$endif}
begin
{$ifdef CPU_WASM32}
  oldLen := WasiStrLen(oldPath);
  newLen := WasiStrLen(newPath);
  if (oldLen = 0) or (newLen = 0) then begin Result := -2; Exit; end;
  oldFd := WasiFindPreopen(oldPath, oldLen, oldRel);
  newFd := WasiFindPreopen(newPath, newLen, newRel);
  if (oldFd < 0) or (newFd < 0) then begin Result := -2; Exit; end;
  if (oldRel >= oldLen) or (newRel >= newLen) then begin Result := -22; Exit; end;
  Result := WasiErr(wasi_path_rename(oldFd, Pointer(Int64(oldPath) + oldRel),
                                     oldLen - oldRel,
                                     newFd, Pointer(Int64(newPath) + newRel),
                                     newLen - newRel));
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendMkdir(path: PChar; mode: Integer): Integer;
{$ifdef CPU_WASM32}
var dirfd, relOfs, pathLen: Integer;
{$endif}
begin
{$ifdef CPU_WASM32}
  pathLen := WasiStrLen(path);
  if pathLen = 0 then begin Result := -2; Exit; end;
  dirfd := WasiFindPreopen(path, pathLen, relOfs);
  if (dirfd < 0) or (relOfs >= pathLen) then begin Result := -2; Exit; end;
  Result := WasiErr(wasi_path_create_directory(dirfd, Pointer(Int64(path) + relOfs),
                       pathLen - relOfs));
  { `mode` has no meaning here: WASI has no permission bits. Ignored
    rather than refused, because a caller passing 0755 is asking for a
    directory, not for a mode. }
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendRmdir(path: PChar): Integer;
{$ifdef CPU_WASM32}
var dirfd, relOfs, pathLen: Integer;
{$endif}
begin
{$ifdef CPU_WASM32}
  pathLen := WasiStrLen(path);
  if pathLen = 0 then begin Result := -2; Exit; end;
  dirfd := WasiFindPreopen(path, pathLen, relOfs);
  if (dirfd < 0) or (relOfs >= pathLen) then begin Result := -2; Exit; end;
  Result := WasiErr(wasi_path_remove_directory(dirfd, Pointer(Int64(path) + relOfs),
                       pathLen - relOfs));
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendChdir(path: PChar): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSymlink(target, linkpath: PChar): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendLink(oldPath, newPath: PChar): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendStat(path: PChar; var info: TPalFileStat): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFstat(handle: Integer; var info: TPalFileStat): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendLstat(path: PChar; var info: TPalFileStat): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFcntl(handle, cmd: Integer; arg: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFsync(handle: Integer): Integer;
begin
{$ifdef CPU_WASM32}
  Result := WasiErr(wasi_fd_sync(handle));
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendFchmod(handle, mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendChmod(path: PChar; mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendUmask(mask: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFtruncate(handle: Integer; length: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendAccess(path: PChar; mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFchown(handle, owner, group: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGeteuid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetuid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetgid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetegid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetppid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetpid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetcwd(buf: PChar; size: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendNanosleep(sec, nsec: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ clock_time_get answers in NANOSECONDS since the epoch, one value, where the
  PAL wants seconds and nanoseconds apart. The `precision` argument is a hint
  and 1000 (a microsecond) asks for no more resolution than any host provides. }
function PalBackendRealtime(var sec, nsec: Int64): Integer;
{$ifdef CPU_WASM32}
var rc, i: Integer; t: Int64;
{$endif}
begin
{$ifdef CPU_WASM32}
  WasiScratch64 := 0;
  rc := wasi_clock_time_get(WASI_CLOCK_REALTIME, 1000, @WasiScratch64);
  if rc <> 0 then begin Result := WasiErr(rc); Exit; end;
  t := WasiScratch64;
  sec := t div 1000000000;
  nsec := t mod 1000000000;
  Result := 0;
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendMmapAnon(len: Int64): Pointer;
begin
  Result := nil;
end;

function PalBackendMmapAnonProt(len: Int64; prot: Integer): Pointer;
begin
  Result := nil;
end;

function PalBackendMprotect(addr: Pointer; len: Int64; prot: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendMunmap(addr: Pointer; len: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSocket(domain, kind, proto: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendConnectUnix(handle: Integer; const path: string): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendBindIpv6(handle: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendConnectIpv6(handle: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendListen(handle, backlog: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendAccept(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendShutdown(handle, how: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSocketClose(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSendToIpv6(handle: Integer; buf: Pointer; len: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRecvFromIpv6(handle: Integer; buf: Pointer; len: Integer; var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendPoll(handle, events, timeoutMs: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendPollSet(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetSockError(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetPeerNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetSockOpt(handle, level, optname: Integer; valPtr: Pointer; lenPtr: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendIoctl(handle: Integer; cmd: NativeInt; argp: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendAcceptIpv6(handle: Integer; var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendMonotonicMillis: Int64;
{$ifdef CPU_WASM32}
var rc, i: Integer; t: Int64;
{$endif}
begin
{$ifdef CPU_WASM32}
  WasiScratch64 := 0;
  rc := wasi_clock_time_get(WASI_CLOCK_MONOTONIC, 1000000, @WasiScratch64);
  if rc <> 0 then begin Result := WasiErr(rc); Exit; end;
  t := WasiScratch64;
  Result := t div 1000000;
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

procedure PalBackendYield;
begin
end;

function PalBackendVfork: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendExecve(path: PChar; argv, envp: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendPipe2(var pipefd: array of Integer; flags: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendDup2(oldFd, newFd: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendKill(pid, sig: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

end.
