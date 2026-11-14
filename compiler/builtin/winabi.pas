unit winabi;

{ The Linux syscall ABI on Windows -- the same in-program translator as
  fbsdabi/obsdabi/minixabi, with kernel32 as the bottom instead of a kernel.

  WHY KERNEL32 AND NOT SYSCALLS. NT's system call numbers change between
  Windows builds and are undocumented; the only stable interface is the DLL
  exports (ntdll, and kernel32 above it). kernel32 is documented and is what
  Wine implements faithfully, so this unit binds it directly: no C runtime
  (msvcrt/ucrt) and no CRT startup.

  CALLING CONVENTION. The imports are declared cdecl like any pxx external;
  under --os=windows every external call site carries the SysV -> Microsoft
  x64 adapter (EmitExternalIndirectCall), so nothing here deals with it. BOOL
  and DWORD results are 32-bit: they are declared LongInt/LongWord so the
  upper half of rax, which Windows leaves undefined, is never read.

  CONTEXT RULES are fbsdabi's: this runs from every syscall site, before the
  heap and TLS exist. No managed types, no heap, no exceptions, no RTL calls,
  locals only plus this unit's few globals.

  PHASE 1 SCOPE (feature-port-windows-pe): the standard handles, memory
  (mmap anonymous, munmap, mprotect, a brk over a reserved region), time,
  process identity and exit, and the harmless no-ops the startup makes
  (signals, arch_prctl, futex with one thread). Files, directories, the
  command line and environment, processes and sockets come next. Anything
  unmapped answers -ENOSYS; set PXX_WINABI_TRACE=1 to have each one named on
  stderr. }

interface

function PXXWinSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;

implementation

const
  LX_EBADF = 9;
  LX_ENOMEM = 12;
  LX_EFAULT = 14;
  LX_EINVAL = 22;
  LX_ENOTTY = 25;
  LX_ENOSYS = 38;
  LX_EIO = 5;

  STD_INPUT_HANDLE = -10;
  STD_OUTPUT_HANDLE = -11;
  STD_ERROR_HANDLE = -12;

  MEM_COMMIT = $1000;
  MEM_RESERVE = $2000;
  MEM_RELEASE = $8000;
  PAGE_NOACCESS = $01;
  PAGE_READONLY = $02;
  PAGE_READWRITE = $04;
  PAGE_EXECUTE_READ = $20;
  PAGE_EXECUTE_READWRITE = $40;

  LX_MAP_FIXED = $10;
  LX_MAP_ANONYMOUS = $20;

  BRK_RESERVE = 1024 * 1024 * 1024;   { 1 GiB of address space, committed on demand }
  WIN_STACK = 8 * 1024 * 1024;        { pewriter's PE_IMAGE_STACK }
  FILETIME_UNIX_EPOCH = 116444736000000000;   { 1601 -> 1970 in 100 ns }
  MAX_FD = 256;

  TraceName: array[0..16] of Byte = (80,88,88,95,87,73,78,65,66,73,95,84,82,65,67,69,0);  { PXX_WINABI_TRACE }
  TraceMsg: array[0..15] of Byte = (119,105,110,97,98,105,58,32,117,110,109,97,112,112,101,100);  { "winabi: unmapped" }

function W_GetStdHandle(which: Int64): Int64; cdecl; external 'kernel32.dll' name 'GetStdHandle';
function W_WriteFile(h, buf, n, done, ovl: Int64): LongInt; cdecl; external 'kernel32.dll' name 'WriteFile';
function W_ReadFile(h, buf, n, done, ovl: Int64): LongInt; cdecl; external 'kernel32.dll' name 'ReadFile';
function W_CloseHandle(h: Int64): LongInt; cdecl; external 'kernel32.dll' name 'CloseHandle';
procedure W_ExitProcess(code: Int64); cdecl; external 'kernel32.dll' name 'ExitProcess';
function W_VirtualAlloc(addr, size, typ, prot: Int64): Int64; cdecl; external 'kernel32.dll' name 'VirtualAlloc';
function W_VirtualFree(addr, size, typ: Int64): LongInt; cdecl; external 'kernel32.dll' name 'VirtualFree';
function W_VirtualProtect(addr, size, prot, old: Int64): LongInt; cdecl; external 'kernel32.dll' name 'VirtualProtect';
function W_GetCurrentProcessId: LongWord; cdecl; external 'kernel32.dll' name 'GetCurrentProcessId';
function W_GetCurrentThreadId: LongWord; cdecl; external 'kernel32.dll' name 'GetCurrentThreadId';
procedure W_GetSystemTimePreciseAsFileTime(ft: Int64); cdecl; external 'kernel32.dll' name 'GetSystemTimePreciseAsFileTime';
function W_QueryUnbiasedInterruptTime(p: Int64): LongInt; cdecl; external 'kernel32.dll' name 'QueryUnbiasedInterruptTime';
procedure W_Sleep(ms: Int64); cdecl; external 'kernel32.dll' name 'Sleep';
function W_SwitchToThread: LongInt; cdecl; external 'kernel32.dll' name 'SwitchToThread';
function W_GetEnvironmentVariableA(name, buf, size: Int64): LongWord; cdecl; external 'kernel32.dll' name 'GetEnvironmentVariableA';
function W_GetFileType(h: Int64): LongWord; cdecl; external 'kernel32.dll' name 'GetFileType';
function W_GetCommandLineW: Int64; cdecl; external 'kernel32.dll' name 'GetCommandLineW';
function W_GetEnvironmentStringsW: Int64; cdecl; external 'kernel32.dll' name 'GetEnvironmentStringsW';

var
  WinFd: array[0..MAX_FD-1] of Int64;   { Linux fd -> HANDLE (FK_HANDLE) }
  WinFdReady: Boolean;
  WinBrkBase, WinBrkCur, WinBrkTop: Int64;
  WinTrace: LongInt;                    { 0 = not asked yet, 1 = off, 2 = on }

function FdHandle(fd: Int64): Int64; forward;

procedure TraceUnmapped(nr: Int64);
var buf: array[0..39] of Byte;
    n, i, sh, dg: Integer;
    done: LongWord;
begin
  if WinTrace = 0 then
  begin
    if W_GetEnvironmentVariableA(Int64(@TraceName[0]), Int64(@buf[0]), 8) > 0 then WinTrace := 2
    else WinTrace := 1;
  end;
  if WinTrace <> 2 then Exit;
  for i := 0 to 15 do buf[i] := TraceMsg[i];
  buf[16] := 32; buf[17] := 48; buf[18] := 120;   { " 0x" }
  n := 19;
  sh := 28;                                     { the Linux number in hex, 8 digits }
  while sh >= 0 do
  begin
    dg := (nr shr sh) and 15;
    if dg < 10 then buf[n] := 48 + dg else buf[n] := 87 + dg;
    Inc(n);
    sh := sh - 4;
  end;
  buf[n] := 10; Inc(n);
  done := 0;
  W_WriteFile(FdHandle(2), Int64(@buf[0]), n, Int64(@done), 0);
end;

function WinProt(prot: Int64): Int64;
begin
  case prot and 7 of
    0: Result := PAGE_NOACCESS;
    1: Result := PAGE_READONLY;
    2, 3: Result := PAGE_READWRITE;
    4, 5: Result := PAGE_EXECUTE_READ;
  else
    Result := PAGE_EXECUTE_READWRITE;
  end;
end;

function WinMmap(addr, len, prot, flags: Int64): Int64;
var r: Int64;
begin
  if (flags and LX_MAP_ANONYMOUS) = 0 then begin Result := -LX_ENOSYS; Exit; end;   { file mappings: phase 2 }
  if (flags and LX_MAP_FIXED) <> 0 then
  begin
    { Only inside a region we reserved (brk): commit it. }
    r := W_VirtualAlloc(addr, len, MEM_COMMIT, WinProt(prot));
    if r = 0 then Result := -LX_ENOMEM else Result := r;
    Exit;
  end;
  if prot = 0 then
    r := W_VirtualAlloc(0, len, MEM_RESERVE, PAGE_NOACCESS)   { a guard/reservation }
  else
    r := W_VirtualAlloc(0, len, MEM_RESERVE or MEM_COMMIT, WinProt(prot));
  if r = 0 then Result := -LX_ENOMEM else Result := r;
end;

{ VirtualFree releases a whole allocation only, from its base. A partial
  munmap (an allocator trimming) is accepted and leaks until exit. }
function WinMunmap(addr: Int64): Int64;
begin
  W_VirtualFree(addr, 0, MEM_RELEASE);
  Result := 0;
end;

function WinMprotect(addr, len, prot: Int64): Int64;
var old: LongWord;
begin
  old := 0;
  if W_VirtualProtect(addr, len, WinProt(prot), Int64(@old)) <> 0 then Result := 0
  else Result := -LX_EINVAL;
end;

function WinBrk(want: Int64): Int64;
var top, r: Int64;
begin
  if WinBrkBase = 0 then
  begin
    r := W_VirtualAlloc(0, BRK_RESERVE, MEM_RESERVE, PAGE_READWRITE);
    if r = 0 then begin Result := 0; Exit; end;
    WinBrkBase := r; WinBrkCur := r; WinBrkTop := r;
  end;
  Result := WinBrkCur;
  if (want < WinBrkBase) or (want > WinBrkBase + BRK_RESERVE) then Exit;
  if want > WinBrkTop then
  begin
    top := (want + $FFFF) and (not Int64($FFFF));
    r := W_VirtualAlloc(WinBrkTop, top - WinBrkTop, MEM_COMMIT, PAGE_READWRITE);
    if r = 0 then Exit;
    WinBrkTop := top;
  end;
  WinBrkCur := want;
  Result := want;
end;

{ The argument block, built once at entry (WIN_PXX_ARGBLOCK). }
var
  ArgOut: Int64;          { next UTF-8 byte to write }

{ One UTF-16 code unit at w (and its low surrogate, if any) to UTF-8 at
  ArgOut. Answers how many code units it consumed. Hand-written rather than
  WideCharToMultiByte: one call per character would be the cost. }
function PutUtf8(w: Int64): Int64;
var c, lo: Int64;
begin
  c := PWord(w)^;
  Result := 1;
  if (c >= $D800) and (c <= $DBFF) then
  begin
    lo := PWord(w + 2)^;
    if (lo >= $DC00) and (lo <= $DFFF) then
    begin
      c := $10000 + ((c - $D800) shl 10) + (lo - $DC00);
      Result := 2;
    end;
  end;
  if c < $80 then
  begin
    PByte(ArgOut)^ := c; ArgOut := ArgOut + 1;
  end
  else if c < $800 then
  begin
    PByte(ArgOut)^ := $C0 or (c shr 6);
    PByte(ArgOut + 1)^ := $80 or (c and $3F);
    ArgOut := ArgOut + 2;
  end
  else if c < $10000 then
  begin
    PByte(ArgOut)^ := $E0 or (c shr 12);
    PByte(ArgOut + 1)^ := $80 or ((c shr 6) and $3F);
    PByte(ArgOut + 2)^ := $80 or (c and $3F);
    ArgOut := ArgOut + 3;
  end
  else
  begin
    PByte(ArgOut)^ := $F0 or (c shr 18);
    PByte(ArgOut + 1)^ := $80 or ((c shr 12) and $3F);
    PByte(ArgOut + 2)^ := $80 or ((c shr 6) and $3F);
    PByte(ArgOut + 3)^ := $80 or (c and $3F);
    ArgOut := ArgOut + 4;
  end;
end;

procedure PutByte(b: Int64);
begin
  PByte(ArgOut)^ := b;
  ArgOut := ArgOut + 1;
end;

{ ---- Files -----------------------------------------------------------------
  The fd table. Each Linux fd is one of:
    FK_HANDLE  a Windows HANDLE (files, pipes, the console)
    FK_MEM     bytes in memory read like a file (/proc/self/environ)
    FK_DIR     a directory: its UTF-16 path for getdents64 and *at calls, and
               the FindFirstFileW enumeration (one page per directory fd:
               the path in the first 2 KiB, the find data after it) }
const
  FK_NONE = 0; FK_HANDLE = 1; FK_MEM = 2; FK_DIR = 3;
  LX_AT_FDCWD = -100;
  LX_O_ACCMODE = 3; LX_O_CREAT = $40; LX_O_EXCL = $80; LX_O_TRUNC = $200;
  LX_O_APPEND = $400; LX_O_DIRECTORY = $10000;
  LX_ENOENT = 2; LX_EACCES = 13; LX_EBUSY = 16; LX_EEXIST = 17; LX_ENOTDIR = 20;
  LX_EISDIR = 21; LX_EMFILE = 24; LX_ESPIPE = 29; LX_ENOSPC = 28;
  LX_ENAMETOOLONG = 36; LX_ENOTEMPTY = 39; LX_EPIPE = 32; LX_ERANGE = 34;
  WPATH = 1024;                        { UTF-16 units in a converted path }
  DIR_FIND = 2048;                     { offset of the find data in a dir page }
  INVALID_HANDLE = -1;
  INVALID_ATTRS = $FFFFFFFF;
  FILE_ATTRIBUTE_READONLY = 1;
  FILE_ATTRIBUTE_DIRECTORY = $10;

  DevNull: array[0..8] of Byte = (47,100,101,118,47,110,117,108,108);   { /dev/null }
  ProcEnviron: array[0..17] of Byte = (47,112,114,111,99,47,115,101,108,102,47,
                                       101,110,118,105,114,111,110);   { /proc/self/environ }
  ProcExe: array[0..13] of Byte = (47,112,114,111,99,47,115,101,108,102,47,
                                   101,120,101);                        { /proc/self/exe }

function W_CreateFileW(name, access, share, sa, disp, flags, tmpl: Int64): Int64; cdecl; external 'kernel32.dll' name 'CreateFileW';
function W_GetLastError: LongWord; cdecl; external 'kernel32.dll' name 'GetLastError';
function W_SetFilePointerEx(h, dist, newPos, method: Int64): LongInt; cdecl; external 'kernel32.dll' name 'SetFilePointerEx';
function W_GetFileInformationByHandle(h, info: Int64): LongInt; cdecl; external 'kernel32.dll' name 'GetFileInformationByHandle';
function W_GetFileAttributesExW(name, level, data: Int64): LongInt; cdecl; external 'kernel32.dll' name 'GetFileAttributesExW';
function W_GetFileAttributesW(name: Int64): LongWord; cdecl; external 'kernel32.dll' name 'GetFileAttributesW';
function W_DeleteFileW(name: Int64): LongInt; cdecl; external 'kernel32.dll' name 'DeleteFileW';
function W_RemoveDirectoryW(name: Int64): LongInt; cdecl; external 'kernel32.dll' name 'RemoveDirectoryW';
function W_CreateDirectoryW(name, sa: Int64): LongInt; cdecl; external 'kernel32.dll' name 'CreateDirectoryW';
function W_MoveFileExW(src, dst, flags: Int64): LongInt; cdecl; external 'kernel32.dll' name 'MoveFileExW';
function W_GetCurrentDirectoryW(n, buf: Int64): LongWord; cdecl; external 'kernel32.dll' name 'GetCurrentDirectoryW';
function W_SetCurrentDirectoryW(name: Int64): LongInt; cdecl; external 'kernel32.dll' name 'SetCurrentDirectoryW';
function W_FlushFileBuffers(h: Int64): LongInt; cdecl; external 'kernel32.dll' name 'FlushFileBuffers';
function W_SetEndOfFile(h: Int64): LongInt; cdecl; external 'kernel32.dll' name 'SetEndOfFile';
function W_FindFirstFileW(name, data: Int64): Int64; cdecl; external 'kernel32.dll' name 'FindFirstFileW';
function W_FindNextFileW(h, data: Int64): LongInt; cdecl; external 'kernel32.dll' name 'FindNextFileW';
function W_FindClose(h: Int64): LongInt; cdecl; external 'kernel32.dll' name 'FindClose';
function W_GetModuleFileNameW(m, buf, n: Int64): LongWord; cdecl; external 'kernel32.dll' name 'GetModuleFileNameW';
function W_CreatePipe(r, w, sa, size: Int64): LongInt; cdecl; external 'kernel32.dll' name 'CreatePipe';
function W_GlobalMemoryStatusEx(st: Int64): LongInt; cdecl; external 'kernel32.dll' name 'GlobalMemoryStatusEx';
function W_GetTickCount64: Int64; cdecl; external 'kernel32.dll' name 'GetTickCount64';
function W_DuplicateHandle(sp, h, dp, outH, access, inherit, opts: Int64): LongInt; cdecl; external 'kernel32.dll' name 'DuplicateHandle';

var
  WinFdKind: array[0..MAX_FD-1] of Byte;
  WinFdMem, WinFdLen, WinFdPos: array[0..MAX_FD-1] of Int64;   { FK_MEM; FK_DIR: page, find handle, state }
  WinFdAppend: array[0..MAX_FD-1] of Boolean;
  WinFdFlags: array[0..MAX_FD-1] of LongInt;                   { the open flags, for F_GETFL }
  WinEnvStart, WinEnvEnd: Int64;                               { the environ strings WinArgBlock wrote }

{ GetLastError as a Linux -errno. }
function WinErr: Int64;
var e: LongWord;
begin
  e := W_GetLastError;
  case e of
    2, 3, 15, 123, 161: Result := -LX_ENOENT;   { file/path not found, bad drive, bad name, bad pathname }
    5, 19: Result := -LX_EACCES;
    6: Result := -LX_EBADF;
    32, 33: Result := -LX_EBUSY;                 { sharing / lock violation }
    80, 183: Result := -LX_EEXIST;
    109, 232: Result := -LX_EPIPE;
    112: Result := -LX_ENOSPC;
    145: Result := -LX_ENOTEMPTY;
    206: Result := -LX_ENAMETOOLONG;
    267: Result := -LX_ENOTDIR;
    8, 14: Result := -LX_ENOMEM;
  else
    Result := -LX_EIO;
  end;
end;

procedure WinFdInit;
var i: Integer;
begin
  if WinFdReady then Exit;
  WinFd[0] := W_GetStdHandle(STD_INPUT_HANDLE);
  WinFd[1] := W_GetStdHandle(STD_OUTPUT_HANDLE);
  WinFd[2] := W_GetStdHandle(STD_ERROR_HANDLE);
  for i := 0 to 2 do
    if WinFd[i] <> 0 then WinFdKind[i] := FK_HANDLE;
  WinFdFlags[0] := 0; WinFdFlags[1] := 1; WinFdFlags[2] := 1;
  WinFdReady := True;
end;

function FdKind(fd: Int64): Integer;
begin
  WinFdInit;
  if (fd < 0) or (fd >= MAX_FD) then Result := FK_NONE
  else Result := WinFdKind[fd];
end;

function FdHandle(fd: Int64): Int64;
begin
  if FdKind(fd) = FK_HANDLE then Result := WinFd[fd] else Result := 0;
end;

function FdAlloc(min: Int64): Int64;
var i: Int64;
begin
  WinFdInit;
  Result := -LX_EMFILE;
  for i := min to MAX_FD - 1 do
    if WinFdKind[i] = FK_NONE then
    begin
      WinFd[i] := 0; WinFdMem[i] := 0; WinFdLen[i] := 0; WinFdPos[i] := 0;
      WinFdAppend[i] := False; WinFdFlags[i] := 0;
      Result := i;
      Exit;
    end;
end;

{ UTF-8 at s (NUL-terminated) -> UTF-16 at dst, NUL-terminated, cap units.
  Answers the length, or -1 when it does not fit. }
function Utf8ToW(s, dst, cap: Int64): Int64;
var c, b, n: Int64;
begin
  n := 0;
  while PByte(s)^ <> 0 do
  begin
    c := PByte(s)^; s := s + 1;
    if c >= $F0 then
    begin
      c := c and 7;
      for b := 1 to 3 do begin c := (c shl 6) or (PByte(s)^ and $3F); if PByte(s)^ <> 0 then s := s + 1; end;
    end
    else if c >= $E0 then
    begin
      c := c and 15;
      for b := 1 to 2 do begin c := (c shl 6) or (PByte(s)^ and $3F); if PByte(s)^ <> 0 then s := s + 1; end;
    end
    else if c >= $C0 then
    begin
      c := ((c and 31) shl 6) or (PByte(s)^ and $3F);
      if PByte(s)^ <> 0 then s := s + 1;
    end;
    if c >= $10000 then
    begin
      if n + 2 >= cap then begin Result := -1; Exit; end;
      c := c - $10000;
      PWord(dst + 2 * n)^ := $D800 + (c shr 10);
      PWord(dst + 2 * n + 2)^ := $DC00 + (c and $3FF);
      n := n + 2;
    end
    else
    begin
      if n + 1 >= cap then begin Result := -1; Exit; end;
      PWord(dst + 2 * n)^ := c;
      n := n + 1;
    end;
  end;
  PWord(dst + 2 * n)^ := 0;
  Result := n;
end;

function PathIs(p: Int64; w: PByte; n: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  if p = 0 then Exit;
  for i := 0 to n - 1 do
    if PByte(p + i)^ <> w[i] then Exit;
  Result := PByte(p + n)^ = 0;
end;

{ A Linux path (relative to dirfd) as a UTF-16 Windows path in dst (WPATH
  units). '/' is a separator Win32 accepts as it is; /dev/null is NUL. An
  absolute path keeps its meaning on the current drive (under Wine, drive Z:
  is the Unix root, so /tmp/x is /tmp/x). Answers 0 or -errno. }
function WinPath(dirfd, path, dst: Int64): Int64;
var n, pre, i: Int64;
begin
  if path = 0 then begin Result := -LX_EFAULT; Exit; end;
  if PathIs(path, @DevNull[0], Length(DevNull)) then
  begin
    PWord(dst)^ := 78; PWord(dst + 2)^ := 85; PWord(dst + 4)^ := 76; PWord(dst + 6)^ := 0;   { NUL }
    Result := 0;
    Exit;
  end;
  pre := 0;
  if (PByte(path)^ <> 47) and (dirfd <> LX_AT_FDCWD) then
  begin
    if FdKind(dirfd) <> FK_DIR then begin Result := -LX_ENOTDIR; Exit; end;
    while PWord(WinFdMem[dirfd] + 2 * pre)^ <> 0 do
    begin
      PWord(dst + 2 * pre)^ := PWord(WinFdMem[dirfd] + 2 * pre)^;
      pre := pre + 1;
    end;
    PWord(dst + 2 * pre)^ := 92; pre := pre + 1;
  end;
  n := Utf8ToW(path, dst + 2 * pre, WPATH - pre);
  if n < 0 then begin Result := -LX_ENAMETOOLONG; Exit; end;
  { A trailing separator names the directory itself; Win32 wants it gone. }
  i := pre + n;
  while (i > 1) and ((PWord(dst + 2 * (i - 1))^ = 47) or (PWord(dst + 2 * (i - 1))^ = 92)) do
  begin
    i := i - 1;
    PWord(dst + 2 * i)^ := 0;
  end;
  Result := 0;
end;

{ FILETIME (100 ns since 1601) at ft -> a Linux timespec at ts. }
procedure FtToTs(ft, ts: Int64);
var t: Int64;
begin
  t := PLongWord(ft)^ or (Int64(PLongWord(ft + 4)^) shl 32);
  t := t - FILETIME_UNIX_EPOCH;
  PInt64(ts)^ := t div 10000000;
  PInt64(ts + 8)^ := (t mod 10000000) * 100;
end;

{ Linux x86-64 struct stat (144 bytes) from attributes, size, three
  FILETIMEs (creation, access, write) and an index for st_ino. }
procedure FillStat(st: Int64; attrs: LongWord; size: Int64; ftC, ftA, ftW: Int64; ino, nlink: Int64);
var i: Integer;
begin
  for i := 0 to 143 do PByte(st + i)^ := 0;
  PInt64(st + 8)^ := ino;
  PInt64(st + 16)^ := nlink;
  if (attrs and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
    PLongWord(st + 24)^ := $41ED                              { S_IFDIR | 0755 }
  else if (attrs and FILE_ATTRIBUTE_READONLY) <> 0 then
    PLongWord(st + 24)^ := $8124                              { S_IFREG | 0444 }
  else
    PLongWord(st + 24)^ := $81A4;                             { S_IFREG | 0644 }
  PInt64(st + 48)^ := size;
  PInt64(st + 56)^ := 4096;
  PInt64(st + 64)^ := (size + 511) shr 9;
  FtToTs(ftA, st + 72);
  FtToTs(ftW, st + 88);
  FtToTs(ftW, st + 104);                                      { ctime: Windows has none; mtime }
end;

function StatPathW(w, st: Int64): Int64;
var d: array[0..8] of LongWord;   { WIN32_FILE_ATTRIBUTE_DATA, 36 bytes }
begin
  if W_GetFileAttributesExW(w, 0, Int64(@d[0])) = 0 then begin Result := WinErr; Exit; end;
  FillStat(st, d[0], (Int64(d[7]) shl 32) or d[8], Int64(@d[1]), Int64(@d[3]), Int64(@d[5]), 1, 1);
  Result := 0;
end;

function WinFstat(fd, st: Int64): Int64;
var h: Int64;
    i: Integer;
    t: LongWord;
    info: array[0..12] of LongWord;   { BY_HANDLE_FILE_INFORMATION, 52 bytes }
begin
  case FdKind(fd) of
    FK_NONE: begin Result := -LX_EBADF; Exit; end;
    FK_DIR: begin Result := StatPathW(WinFdMem[fd], st); Exit; end;
    FK_MEM:
      begin
        for i := 0 to 143 do PByte(st + i)^ := 0;
        PLongWord(st + 24)^ := $8124;
        PInt64(st + 56)^ := 4096;
        Result := 0;
        Exit;
      end;
  end;
  h := WinFd[fd];
  t := W_GetFileType(h);
  if t = 1 then                                       { FILE_TYPE_DISK }
  begin
    if W_GetFileInformationByHandle(h, Int64(@info[0])) <> 0 then
    begin
      FillStat(st, info[0], (Int64(info[8]) shl 32) or info[9],
               Int64(@info[1]), Int64(@info[3]), Int64(@info[5]),
               (Int64(info[11]) shl 32) or info[12], info[10]);
      Result := 0;
      Exit;
    end;
  end;
  for i := 0 to 143 do PByte(st + i)^ := 0;
  if t = 2 then PLongWord(st + 24)^ := $2190          { FILE_TYPE_CHAR: S_IFCHR | 0620 }
  else if t = 3 then PLongWord(st + 24)^ := $1180     { FILE_TYPE_PIPE: S_IFIFO | 0600 }
  else PLongWord(st + 24)^ := $8180;                  { S_IFREG | 0600 }
  PInt64(st + 56)^ := 4096;                           { st_blksize }
  Result := 0;
end;

{ newfstatat / stat / lstat. There are no symlinks to tell apart here. }
function WinStatAt(dirfd, path, st, flags: Int64): Int64;
var w: array[0..WPATH-1] of Word;
    r: Int64;
begin
  if ((flags and $1000) <> 0) and ((path = 0) or (PByte(path)^ = 0)) then   { AT_EMPTY_PATH }
  begin
    Result := WinFstat(dirfd, st);
    Exit;
  end;
  r := WinPath(dirfd, path, Int64(@w[0]));
  if r < 0 then begin Result := r; Exit; end;
  Result := StatPathW(Int64(@w[0]), st);
end;

{ /proc/self/environ: the strings WinArgBlock already laid out as envp,
  which are NUL-separated exactly as the file is. }
function OpenMem(buf, len, flags: Int64): Int64;
var fd: Int64;
begin
  fd := FdAlloc(3);
  if fd < 0 then begin Result := fd; Exit; end;
  WinFdKind[fd] := FK_MEM;
  WinFdMem[fd] := buf; WinFdLen[fd] := len; WinFdPos[fd] := 0;
  WinFdFlags[fd] := flags;
  Result := fd;
end;

function OpenDir(w, flags: Int64): Int64;
var fd, page, i: Int64;
begin
  fd := FdAlloc(3);
  if fd < 0 then begin Result := fd; Exit; end;
  page := W_VirtualAlloc(0, 4096, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE);
  if page = 0 then begin Result := -LX_ENOMEM; Exit; end;
  i := 0;
  while (i < DIR_FIND div 2 - 1) and (PWord(w + 2 * i)^ <> 0) do
  begin
    PWord(page + 2 * i)^ := PWord(w + 2 * i)^;
    i := i + 1;
  end;
  PWord(page + 2 * i)^ := 0;
  WinFdKind[fd] := FK_DIR;
  WinFdMem[fd] := page;
  WinFdLen[fd] := INVALID_HANDLE;   { no enumeration yet }
  WinFdPos[fd] := 0;                { 0 = start, 1 = an entry is pending in the page, 2 = done }
  WinFdFlags[fd] := flags;
  Result := fd;
end;

function WinOpenAt(dirfd, path, flags, mode: Int64): Int64;
var w: array[0..WPATH-1] of Word;
    r, h, fd, access, disp, attrs: Int64;
    a: LongWord;
begin
  if PathIs(path, @ProcEnviron[0], Length(ProcEnviron)) then
  begin
    Result := OpenMem(WinEnvStart, WinEnvEnd - WinEnvStart, flags);
    Exit;
  end;
  r := WinPath(dirfd, path, Int64(@w[0]));
  if r < 0 then begin Result := r; Exit; end;
  a := W_GetFileAttributesW(Int64(@w[0]));
  if (a <> INVALID_ATTRS) and ((a and FILE_ATTRIBUTE_DIRECTORY) <> 0) then
  begin
    if (flags and LX_O_ACCMODE) <> 0 then begin Result := -LX_EISDIR; Exit; end;
    Result := OpenDir(Int64(@w[0]), flags);
    Exit;
  end;
  if (flags and LX_O_DIRECTORY) <> 0 then
  begin
    if a = INVALID_ATTRS then Result := -LX_ENOENT else Result := -LX_ENOTDIR;
    Exit;
  end;
  case flags and LX_O_ACCMODE of
    0: access := $80000000;                          { GENERIC_READ }
    1: access := $40000000;                          { GENERIC_WRITE }
  else
    access := $C0000000;
  end;
  if (flags and LX_O_CREAT) <> 0 then
  begin
    if (flags and LX_O_EXCL) <> 0 then disp := 1     { CREATE_NEW }
    else if (flags and LX_O_TRUNC) <> 0 then disp := 2   { CREATE_ALWAYS }
    else disp := 4;                                  { OPEN_ALWAYS }
  end
  else if (flags and LX_O_TRUNC) <> 0 then disp := 5 { TRUNCATE_EXISTING }
  else disp := 3;                                    { OPEN_EXISTING }
  attrs := $80;                                      { FILE_ATTRIBUTE_NORMAL }
  if ((flags and LX_O_CREAT) <> 0) and ((mode and $92) = 0) then attrs := FILE_ATTRIBUTE_READONLY;
  h := W_CreateFileW(Int64(@w[0]), access, 7, 0, disp, attrs, 0);   { share read|write|delete }
  if h = INVALID_HANDLE then begin Result := WinErr; Exit; end;
  fd := FdAlloc(3);
  if fd < 0 then begin W_CloseHandle(h); Result := fd; Exit; end;
  WinFdKind[fd] := FK_HANDLE;
  WinFd[fd] := h;
  WinFdAppend[fd] := (flags and LX_O_APPEND) <> 0;
  WinFdFlags[fd] := flags;
  Result := fd;
end;

function WinWrite(fd, buf, n: Int64): Int64;
var h, z: Int64;
    done: LongWord;
begin
  h := FdHandle(fd);
  if h = 0 then
  begin
    if FdKind(fd) = FK_NONE then Result := -LX_EBADF else Result := -LX_EBADF;
    Exit;
  end;
  if n > $7FFFFFFF then n := $7FFFFFFF;
  if WinFdAppend[fd] then
  begin
    z := 0;
    W_SetFilePointerEx(h, 0, Int64(@z), 2);          { FILE_END }
  end;
  done := 0;
  if W_WriteFile(h, buf, n, Int64(@done), 0) = 0 then Result := WinErr
  else Result := done;
end;

function WinRead(fd, buf, n: Int64): Int64;
var h, i, k: Int64;
    done: LongWord;
begin
  case FdKind(fd) of
    FK_NONE: begin Result := -LX_EBADF; Exit; end;
    FK_DIR: begin Result := -LX_EISDIR; Exit; end;
    FK_MEM:
      begin
        k := WinFdLen[fd] - WinFdPos[fd];
        if k > n then k := n;
        if k < 0 then k := 0;
        for i := 0 to k - 1 do PByte(buf + i)^ := PByte(WinFdMem[fd] + WinFdPos[fd] + i)^;
        WinFdPos[fd] := WinFdPos[fd] + k;
        Result := k;
        Exit;
      end;
  end;
  h := WinFd[fd];
  if n > $7FFFFFFF then n := $7FFFFFFF;
  done := 0;
  { A broken pipe or closed console reads as end of file, as on Linux. }
  if W_ReadFile(h, buf, n, Int64(@done), 0) = 0 then
  begin
    if W_GetLastError = 109 then Result := 0 else Result := WinErr;   { ERROR_BROKEN_PIPE }
  end
  else Result := done;
end;

{ pread/pwrite: an OVERLAPPED carrying the offset. Unlike Linux this moves
  the file position; nothing in the runtime mixes the two on one fd. }
function WinPrw(fd, buf, n, off: Int64; isWrite: Boolean): Int64;
var h: Int64;
    done: LongWord;
    ov: array[0..3] of Int64;   { OVERLAPPED, 32 bytes }
begin
  h := FdHandle(fd);
  if h = 0 then begin Result := -LX_EBADF; Exit; end;
  ov[0] := 0; ov[1] := 0; ov[2] := 0; ov[3] := 0;
  PLongWord(Int64(@ov[0]) + 16)^ := off and $FFFFFFFF;
  PLongWord(Int64(@ov[0]) + 20)^ := (off shr 32) and $FFFFFFFF;
  done := 0;
  if isWrite then
  begin
    if W_WriteFile(h, buf, n, Int64(@done), Int64(@ov[0])) = 0 then begin Result := WinErr; Exit; end;
  end
  else if W_ReadFile(h, buf, n, Int64(@done), Int64(@ov[0])) = 0 then
  begin
    if W_GetLastError = 38 then Result := 0 else Result := WinErr;   { ERROR_HANDLE_EOF }
    Exit;
  end;
  Result := done;
end;

function WinPrwv(fd, iov, cnt, off: Int64; isWrite: Boolean): Int64;
var i, r, total, len: Int64;
begin
  total := 0;
  for i := 0 to cnt - 1 do
  begin
    len := PInt64(iov + 16 * i + 8)^;
    r := WinPrw(fd, PInt64(iov + 16 * i)^, len, off + total, isWrite);
    if r < 0 then
    begin
      if total = 0 then total := r;
      Break;
    end;
    total := total + r;
    if r < len then Break;
  end;
  Result := total;
end;

function WinLseek(fd, off, whence: Int64): Int64;
var h, np: Int64;
    t: LongWord;
begin
  case FdKind(fd) of
    FK_NONE: begin Result := -LX_EBADF; Exit; end;
    FK_MEM:
      begin
        if whence = 0 then np := off
        else if whence = 1 then np := WinFdPos[fd] + off
        else np := WinFdLen[fd] + off;
        if np < 0 then begin Result := -LX_EINVAL; Exit; end;
        WinFdPos[fd] := np;
        Result := np;
        Exit;
      end;
    FK_DIR:
      begin
        { only a rewind: restart the enumeration }
        if WinFdLen[fd] <> INVALID_HANDLE then W_FindClose(WinFdLen[fd]);
        WinFdLen[fd] := INVALID_HANDLE;
        WinFdPos[fd] := 0;
        Result := 0;
        Exit;
      end;
  end;
  h := WinFd[fd];
  t := W_GetFileType(h);
  if (t = 2) or (t = 3) then begin Result := -LX_ESPIPE; Exit; end;
  np := 0;
  if W_SetFilePointerEx(h, off, Int64(@np), whence) = 0 then Result := WinErr
  else Result := np;
end;

function WinWritev(fd, iov, cnt: Int64): Int64;
var i: Int64;
    r, total: Int64;
begin
  total := 0;
  for i := 0 to cnt - 1 do
  begin
    r := WinWrite(fd, PInt64(iov + 16 * i)^, PInt64(iov + 16 * i + 8)^);
    if r < 0 then
    begin
      if total = 0 then total := r;
      Break;
    end;
    total := total + r;
  end;
  Result := total;
end;

function WinReadv(fd, iov, cnt: Int64): Int64;
var i: Int64;
    r, total: Int64;
begin
  total := 0;
  for i := 0 to cnt - 1 do
  begin
    r := WinRead(fd, PInt64(iov + 16 * i)^, PInt64(iov + 16 * i + 8)^);
    if r < 0 then
    begin
      if total = 0 then total := r;
      Break;
    end;
    total := total + r;
    if r < PInt64(iov + 16 * i + 8)^ then Break;
  end;
  Result := total;
end;

function WinClose(fd: Int64): Int64;
begin
  case FdKind(fd) of
    FK_NONE: begin Result := -LX_EBADF; Exit; end;
    FK_HANDLE: W_CloseHandle(WinFd[fd]);
    FK_DIR:
      begin
        if WinFdLen[fd] <> INVALID_HANDLE then W_FindClose(WinFdLen[fd]);
        W_VirtualFree(WinFdMem[fd], 0, MEM_RELEASE);
      end;
  end;
  WinFdKind[fd] := FK_NONE;
  WinFd[fd] := 0;
  Result := 0;
end;

{ getdents64 over FindFirstFileW/FindNextFileW. The entry that did not fit
  stays pending in the find data for the next call. linux_dirent64: d_ino 8,
  d_off 8, d_reclen 2, d_type 1, the name and its NUL, padded to 8. }
function WinGetdents(fd, buf, cnt: Int64): Int64;
var page, fdat, pos, i, n, rec: Int64;
    w: array[0..WPATH+2] of Word;
    tmp: array[0..1023] of Byte;
begin
  if FdKind(fd) <> FK_DIR then
  begin
    if FdKind(fd) = FK_NONE then Result := -LX_EBADF else Result := -LX_ENOTDIR;
    Exit;
  end;
  page := WinFdMem[fd];
  fdat := page + DIR_FIND;
  if WinFdPos[fd] = 0 then
  begin
    i := 0;
    while PWord(page + 2 * i)^ <> 0 do begin w[i] := PWord(page + 2 * i)^; i := i + 1; end;
    w[i] := 92; w[i + 1] := 42; w[i + 2] := 0;          { \* }
    WinFdLen[fd] := W_FindFirstFileW(Int64(@w[0]), fdat);
    if WinFdLen[fd] = INVALID_HANDLE then begin WinFdPos[fd] := 2; Result := WinErr; Exit; end;
    WinFdPos[fd] := 1;
  end;
  pos := 0;
  while WinFdPos[fd] = 1 do
  begin
    { the name (WIN32_FIND_DATAW.cFileName at 44) as UTF-8 }
    ArgOut := Int64(@tmp[0]);
    i := fdat + 44;
    while (PWord(i)^ <> 0) and (ArgOut < Int64(@tmp[0]) + 1016) do i := i + 2 * PutUtf8(i);
    PByte(ArgOut)^ := 0;
    n := ArgOut - Int64(@tmp[0]);
    rec := (19 + n + 1 + 7) and (not Int64(7));
    if pos + rec > cnt then
    begin
      if pos = 0 then Result := -LX_EINVAL else Result := pos;
      Exit;
    end;
    PInt64(buf + pos)^ := pos + 1;                       { d_ino: nonzero }
    PInt64(buf + pos + 8)^ := pos + rec;                 { d_off }
    PWord(buf + pos + 16)^ := rec;
    if (PLongWord(fdat)^ and FILE_ATTRIBUTE_DIRECTORY) <> 0 then PByte(buf + pos + 18)^ := 4   { DT_DIR }
    else PByte(buf + pos + 18)^ := 8;                    { DT_REG }
    for i := 0 to n do PByte(buf + pos + 19 + i)^ := tmp[i];
    for i := 19 + n + 1 to rec - 1 do PByte(buf + pos + i)^ := 0;
    pos := pos + rec;
    if W_FindNextFileW(WinFdLen[fd], fdat) = 0 then WinFdPos[fd] := 2;
  end;
  Result := pos;
end;

function WinMkdirAt(dirfd, path: Int64): Int64;
var w: array[0..WPATH-1] of Word;
    r: Int64;
begin
  r := WinPath(dirfd, path, Int64(@w[0]));
  if r < 0 then begin Result := r; Exit; end;
  if W_CreateDirectoryW(Int64(@w[0]), 0) = 0 then Result := WinErr else Result := 0;
end;

function WinUnlinkAt(dirfd, path, flags: Int64): Int64;
var w: array[0..WPATH-1] of Word;
    r: Int64;
    a: LongWord;
begin
  r := WinPath(dirfd, path, Int64(@w[0]));
  if r < 0 then begin Result := r; Exit; end;
  a := W_GetFileAttributesW(Int64(@w[0]));
  if (flags and $200) <> 0 then                       { AT_REMOVEDIR }
  begin
    if (a <> INVALID_ATTRS) and ((a and FILE_ATTRIBUTE_DIRECTORY) = 0) then begin Result := -LX_ENOTDIR; Exit; end;
    if W_RemoveDirectoryW(Int64(@w[0])) = 0 then Result := WinErr else Result := 0;
  end
  else
  begin
    if (a <> INVALID_ATTRS) and ((a and FILE_ATTRIBUTE_DIRECTORY) <> 0) then begin Result := -LX_EISDIR; Exit; end;
    if W_DeleteFileW(Int64(@w[0])) = 0 then Result := WinErr else Result := 0;
  end;
end;

function WinRenameAt(odir, opath, ndir, npath: Int64): Int64;
var w1, w2: array[0..WPATH-1] of Word;
    r: Int64;
begin
  r := WinPath(odir, opath, Int64(@w1[0]));
  if r < 0 then begin Result := r; Exit; end;
  r := WinPath(ndir, npath, Int64(@w2[0]));
  if r < 0 then begin Result := r; Exit; end;
  if W_MoveFileExW(Int64(@w1[0]), Int64(@w2[0]), 1) = 0 then Result := WinErr   { REPLACE_EXISTING }
  else Result := 0;
end;

function WinAccessAt(dirfd, path: Int64): Int64;
var w: array[0..WPATH-1] of Word;
    r: Int64;
begin
  r := WinPath(dirfd, path, Int64(@w[0]));
  if r < 0 then begin Result := r; Exit; end;
  if W_GetFileAttributesW(Int64(@w[0])) = INVALID_ATTRS then Result := WinErr else Result := 0;
end;

{ getcwd: UTF-8, with '/' kept as Windows writes it ('\'): a Windows path
  is what the program will hand back to Windows. Linux answers the length
  including the NUL. }
function WinGetcwd(buf, size: Int64): Int64;
var w: array[0..WPATH-1] of Word;
    n, i, t: Int64;
    tmp: array[0..4095] of Byte;
begin
  n := W_GetCurrentDirectoryW(WPATH, Int64(@w[0]));
  if (n = 0) or (n >= WPATH) then begin Result := -LX_ENAMETOOLONG; Exit; end;
  ArgOut := Int64(@tmp[0]);
  i := 0;
  while i < n do i := i + PutUtf8(Int64(@w[0]) + 2 * i);
  t := ArgOut - Int64(@tmp[0]);
  if t + 1 > size then begin Result := -LX_ERANGE; Exit; end;
  for i := 0 to t - 1 do PByte(buf + i)^ := tmp[i];
  PByte(buf + t)^ := 0;
  Result := t + 1;
end;

function WinChdir(path: Int64): Int64;
var w: array[0..WPATH-1] of Word;
    r: Int64;
begin
  r := WinPath(LX_AT_FDCWD, path, Int64(@w[0]));
  if r < 0 then begin Result := r; Exit; end;
  if W_SetCurrentDirectoryW(Int64(@w[0])) = 0 then Result := WinErr else Result := 0;
end;

function WinFchdir(fd: Int64): Int64;
begin
  if FdKind(fd) <> FK_DIR then begin Result := -LX_ENOTDIR; Exit; end;
  if W_SetCurrentDirectoryW(WinFdMem[fd]) = 0 then Result := WinErr else Result := 0;
end;

function WinFtruncate(fd, len: Int64): Int64;
var h, cur, z: Int64;
begin
  h := FdHandle(fd);
  if h = 0 then begin Result := -LX_EBADF; Exit; end;
  cur := 0; z := 0;
  W_SetFilePointerEx(h, 0, Int64(@cur), 1);
  if W_SetFilePointerEx(h, len, Int64(@z), 0) = 0 then begin Result := WinErr; Exit; end;
  if W_SetEndOfFile(h) = 0 then Result := WinErr else Result := 0;
  W_SetFilePointerEx(h, cur, Int64(@z), 0);
end;

function WinFsync(fd: Int64): Int64;
var h: Int64;
begin
  h := FdHandle(fd);
  if h = 0 then
  begin
    if FdKind(fd) = FK_NONE then Result := -LX_EBADF else Result := 0;
    Exit;
  end;
  W_FlushFileBuffers(h);   { a console or pipe refuses; Linux answers EINVAL there, nothing checks }
  Result := 0;
end;

{ readlink: /proc/self/exe only (there are no symlinks to read). }
function WinReadlinkAt(dirfd, path, buf, cap: Int64): Int64;
var w: array[0..WPATH-1] of Word;
    n, i, t: Int64;
    tmp: array[0..4095] of Byte;
begin
  if not PathIs(path, @ProcExe[0], Length(ProcExe)) then
  begin
    if WinAccessAt(dirfd, path) = 0 then Result := -LX_EINVAL else Result := -LX_ENOENT;
    Exit;
  end;
  n := W_GetModuleFileNameW(0, Int64(@w[0]), WPATH);
  if n = 0 then begin Result := WinErr; Exit; end;
  ArgOut := Int64(@tmp[0]);
  i := 0;
  while i < n do i := i + PutUtf8(Int64(@w[0]) + 2 * i);
  t := ArgOut - Int64(@tmp[0]);
  if t > cap then t := cap;
  for i := 0 to t - 1 do PByte(buf + i)^ := tmp[i];
  Result := t;
end;

function WinPipe(fds: Int64): Int64;
var r, w, a, b: Int64;
begin
  r := 0; w := 0;
  if W_CreatePipe(Int64(@r), Int64(@w), 0, 0) = 0 then begin Result := WinErr; Exit; end;
  a := FdAlloc(3);
  if a < 0 then begin W_CloseHandle(r); W_CloseHandle(w); Result := a; Exit; end;
  WinFdKind[a] := FK_HANDLE; WinFd[a] := r;
  b := FdAlloc(3);
  if b < 0 then begin WinClose(a); W_CloseHandle(w); Result := b; Exit; end;
  WinFdKind[b] := FK_HANDLE; WinFd[b] := w; WinFdFlags[b] := 1;
  PLongInt(fds)^ := a;
  PLongInt(fds + 4)^ := b;
  Result := 0;
end;

{ dup / dup2 / dup3. A handle is duplicated; a memory or directory fd is
  copied (its position is then not shared, the one difference from Linux). }
function WinDupInto(fd, nfd: Int64): Int64;
var h, page: Int64;
begin
  WinFdKind[nfd] := WinFdKind[fd];
  WinFdMem[nfd] := WinFdMem[fd]; WinFdLen[nfd] := WinFdLen[fd]; WinFdPos[nfd] := WinFdPos[fd];
  WinFdAppend[nfd] := WinFdAppend[fd]; WinFdFlags[nfd] := WinFdFlags[fd];
  if WinFdKind[fd] = FK_HANDLE then
  begin
    h := 0;
    if W_DuplicateHandle(-1, WinFd[fd], -1, Int64(@h), 0, 0, 2) = 0 then   { DUPLICATE_SAME_ACCESS }
    begin
      WinFdKind[nfd] := FK_NONE;
      Result := WinErr;
      Exit;
    end;
    WinFd[nfd] := h;
  end
  else if WinFdKind[fd] = FK_DIR then
  begin
    page := W_VirtualAlloc(0, 4096, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE);
    if page = 0 then begin WinFdKind[nfd] := FK_NONE; Result := -LX_ENOMEM; Exit; end;
    for h := 0 to DIR_FIND - 1 do PByte(page + h)^ := PByte(WinFdMem[fd] + h)^;
    WinFdMem[nfd] := page;
    WinFdLen[nfd] := INVALID_HANDLE;
    WinFdPos[nfd] := 0;
  end;
  Result := nfd;
end;

{ dup2 / dup3: onto target, closing whatever was there. }
function WinDup2(fd, target: Int64): Int64;
begin
  if FdKind(fd) = FK_NONE then begin Result := -LX_EBADF; Exit; end;
  if (target < 0) or (target >= MAX_FD) then begin Result := -LX_EBADF; Exit; end;
  if target = fd then begin Result := fd; Exit; end;
  if WinFdKind[target] <> FK_NONE then WinClose(target);
  Result := WinDupInto(fd, target);
end;

{ dup / F_DUPFD: the lowest free fd at or above min. }
function WinDupMin(fd, min: Int64): Int64;
var nfd: Int64;
begin
  if FdKind(fd) = FK_NONE then begin Result := -LX_EBADF; Exit; end;
  nfd := FdAlloc(min);
  if nfd < 0 then begin Result := nfd; Exit; end;
  Result := WinDupInto(fd, nfd);
end;

function WinFcntl(fd, cmd, arg: Int64): Int64;
begin
  if FdKind(fd) = FK_NONE then begin Result := -LX_EBADF; Exit; end;
  case cmd of
    0, 1030: Result := WinDupMin(fd, arg);          { F_DUPFD, F_DUPFD_CLOEXEC }
    1: Result := 0;                                 { F_GETFD }
    2: Result := 0;                                 { F_SETFD }
    3: Result := WinFdFlags[fd];                    { F_GETFL }
    4: begin                                        { F_SETFL: O_APPEND only }
         WinFdAppend[fd] := (arg and LX_O_APPEND) <> 0;
         Result := 0;
       end;
  else
    Result := 0;                                    { locks: one process }
  end;
end;

function WinClockGettime(clk, ts: Int64): Int64;
var ft: Int64;
begin
  if clk = 0 then
  begin
    ft := 0;
    W_GetSystemTimePreciseAsFileTime(Int64(@ft));
    ft := ft - FILETIME_UNIX_EPOCH;
    PInt64(ts)^ := ft div 10000000;
    PInt64(ts + 8)^ := (ft mod 10000000) * 100;
  end
  else
  begin
    { Monotonic, in 100 ns units, not counting sleep (Linux's MONOTONIC
      does not count suspend either). Constant divisors only: this unit has
      no divide-by-zero stub to call. }
    ft := 0;
    W_QueryUnbiasedInterruptTime(Int64(@ft));
    PInt64(ts)^ := ft div 10000000;
    PInt64(ts + 8)^ := (ft mod 10000000) * 100;
  end;
  Result := 0;
end;

function WinNanosleep(req: Int64): Int64;
var ms: Int64;
begin
  if req = 0 then begin Result := -LX_EFAULT; Exit; end;
  ms := PInt64(req)^ * 1000 + (PInt64(req + 8)^ + 999999) div 1000000;
  W_Sleep(ms);
  Result := 0;
end;

function WinGetrlimit(res, rl: Int64): Int64;
begin
  if res = 3 then                               { RLIMIT_STACK }
  begin
    PInt64(rl)^ := WIN_STACK;
    PInt64(rl + 8)^ := WIN_STACK;
  end
  else
  begin
    PInt64(rl)^ := -1;                          { RLIM_INFINITY }
    PInt64(rl + 8)^ := -1;
  end;
  Result := 0;
end;

{ uname: struct utsname is six 65-byte fields. }
function WinUname(u: Int64): Int64;
const Sys: array[0..6] of Byte = (87,105,110,100,111,119,115);   { Windows }
      Mach: array[0..5] of Byte = (120,56,54,95,54,52);           { x86_64 }
var i: Integer;
begin
  for i := 0 to 6 * 65 - 1 do PByte(u + i)^ := 0;
  for i := 0 to 6 do PByte(u + i)^ := Sys[i];
  for i := 0 to 5 do PByte(u + 4 * 65 + i)^ := Mach[i];
  Result := 0;
end;

{ The Linux initial-stack image: [count] argc argv[0..argc-1] NULL envp[...]
  NULL AT_NULL 0 (+ a zero to make count even), then the UTF-8 strings.

  The command line is split by the Microsoft C runtime's rules, which are
  what every Windows program's argv means: argv[0] runs to the first blank
  or is quoted with no escapes; after it, blanks separate arguments outside
  quotes, 2n backslashes before a quote give n and the quote toggles quoting,
  2n+1 give n and a literal quote, other backslashes are literal, and `""`
  inside quotes is one literal quote. Environment entries that start with
  '=' (the per-drive current directories) are not variables and are left
  out. }
function WinArgBlock: Int64;
var cmd, env, p, q, blk, ptrs, total: Int64;
    cmdLen, envLen, nEnv, nPtr, argc, n, i: Int64;
    inQ: Boolean;
begin
  cmd := W_GetCommandLineW;
  env := W_GetEnvironmentStringsW;
  cmdLen := 0;
  if cmd <> 0 then
    while PWord(cmd + 2 * cmdLen)^ <> 0 do cmdLen := cmdLen + 1;
  envLen := 0; nEnv := 0;
  if env <> 0 then
    while PWord(env + 2 * envLen)^ <> 0 do
    begin
      nEnv := nEnv + 1;
      while PWord(env + 2 * envLen)^ <> 0 do envLen := envLen + 1;
      envLen := envLen + 1;
    end;
  { pointer slots: count, argc, at most cmdLen+1 args, NULL, envs, NULL, 2 auxv, pad }
  nPtr := 1 + 1 + (cmdLen + 1) + 1 + nEnv + 1 + 2 + 1;
  total := 8 * nPtr + 4 * cmdLen + 4 * envLen + cmdLen + 16;
  blk := W_VirtualAlloc(0, total, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE);
  if blk = 0 then W_ExitProcess(127);
  ArgOut := blk + 8 * nPtr;
  ptrs := blk + 16;
  argc := 0;
  p := cmd;
  if (cmd <> 0) and (cmdLen > 0) then
  begin
    { argv[0] }
    PInt64(ptrs)^ := ArgOut; ptrs := ptrs + 8; argc := argc + 1;
    if PWord(p)^ = 34 then
    begin
      p := p + 2;
      while (PWord(p)^ <> 0) and (PWord(p)^ <> 34) do p := p + 2 * PutUtf8(p);
      if PWord(p)^ = 34 then p := p + 2;
    end
    else
      while (PWord(p)^ <> 0) and (PWord(p)^ <> 32) and (PWord(p)^ <> 9) do
        p := p + 2 * PutUtf8(p);
    PutByte(0);
    { the rest }
    while True do
    begin
      while (PWord(p)^ = 32) or (PWord(p)^ = 9) do p := p + 2;
      if PWord(p)^ = 0 then Break;
      PInt64(ptrs)^ := ArgOut; ptrs := ptrs + 8; argc := argc + 1;
      inQ := False;
      while PWord(p)^ <> 0 do
      begin
        if ((PWord(p)^ = 32) or (PWord(p)^ = 9)) and not inQ then Break;
        if PWord(p)^ = 92 then
        begin
          q := p; n := 0;
          while PWord(q)^ = 92 do begin q := q + 2; n := n + 1; end;
          if PWord(q)^ = 34 then
          begin
            for i := 1 to n shr 1 do PutByte(92);
            if (n and 1) <> 0 then begin PutByte(34); p := q + 2; end
            else p := q;               { the quote toggles, next turn }
          end
          else
          begin
            for i := 1 to n do PutByte(92);
            p := q;
          end;
        end
        else if PWord(p)^ = 34 then
        begin
          if inQ and (PWord(p + 2)^ = 34) then begin PutByte(34); p := p + 4; end
          else begin inQ := not inQ; p := p + 2; end;
        end
        else
          p := p + 2 * PutUtf8(p);
      end;
      PutByte(0);
    end;
  end;
  PInt64(ptrs)^ := 0; ptrs := ptrs + 8;              { argv's NULL }
  WinEnvStart := ArgOut;                             { /proc/self/environ is these strings }
  p := env;
  if env <> 0 then
    while PWord(p)^ <> 0 do
    begin
      if PWord(p)^ <> 61 then                         { not '=C:=C:\...' }
      begin
        PInt64(ptrs)^ := ArgOut; ptrs := ptrs + 8;
        while PWord(p)^ <> 0 do p := p + 2 * PutUtf8(p);
        PutByte(0);
      end
      else
        while PWord(p)^ <> 0 do p := p + 2;
      p := p + 2;
    end;
  WinEnvEnd := ArgOut;
  PInt64(ptrs)^ := 0; ptrs := ptrs + 8;              { envp's NULL }
  PInt64(ptrs)^ := 0; ptrs := ptrs + 8;              { AT_NULL }
  PInt64(ptrs)^ := 0; ptrs := ptrs + 8;
  PInt64(blk + 8)^ := argc;
  n := (ptrs - (blk + 8)) shr 3;
  if (n and 1) <> 0 then begin PInt64(ptrs)^ := 0; n := n + 1; end;
  PInt64(blk)^ := n;
  Result := blk;
end;

{ sysinfo: uptime and memory (Linux struct sysinfo, 112 bytes, mem_unit 1). }
function WinSysinfo(si: Int64): Int64;
var ms: array[0..7] of Int64;   { MEMORYSTATUSEX, 64 bytes }
    i: Integer;
begin
  for i := 0 to 111 do PByte(si + i)^ := 0;
  for i := 0 to 7 do ms[i] := 0;
  PLongWord(Int64(@ms[0]))^ := 64;
  W_GlobalMemoryStatusEx(Int64(@ms[0]));
  PInt64(si)^ := W_GetTickCount64 div 1000;
  PInt64(si + 32)^ := ms[1];                 { totalram = ullTotalPhys }
  PInt64(si + 40)^ := ms[2];                 { freeram = ullAvailPhys }
  PInt64(si + 64)^ := ms[3] - ms[1];         { totalswap: the page file beyond RAM }
  if PInt64(si + 64)^ < 0 then PInt64(si + 64)^ := 0;
  PInt64(si + 72)^ := ms[4] - ms[2];
  if PInt64(si + 72)^ < 0 then PInt64(si + 72)^ := 0;
  PWord(si + 80)^ := 1;
  PLongWord(si + 104)^ := 1;
  Result := 0;
end;

function PXXWinSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;
begin
  case nr of
    $7F000002: Result := WinArgBlock;             { WIN_PXX_ARGBLOCK: the entry stub }
    0: Result := WinRead(a0, a1, a2);
    1: Result := WinWrite(a0, a1, a2);
    2: Result := WinOpenAt(LX_AT_FDCWD, a0, a1, a2);              { open }
    3: Result := WinClose(a0);
    4, 6: Result := WinStatAt(LX_AT_FDCWD, a0, a1, 0);           { stat, lstat }
    5: Result := WinFstat(a0, a1);
    8: Result := WinLseek(a0, a1, a2);
    17: Result := WinPrw(a0, a1, a2, a3, False);                  { pread64 }
    18: Result := WinPrw(a0, a1, a2, a3, True);                   { pwrite64 }
    19: Result := WinReadv(a0, a1, a2);
    21: Result := WinAccessAt(LX_AT_FDCWD, a0);                   { access }
    22: Result := WinPipe(a0);
    32: Result := WinDupMin(a0, 0);
    33: Result := WinDup2(a0, a1);
    72: Result := WinFcntl(a0, a1, a2);
    74, 75: Result := WinFsync(a0);                               { fsync, fdatasync }
    76: Result := -LX_ENOSYS;                                     { truncate by path: phase 2b }
    77: Result := WinFtruncate(a0, a1);
    79: Result := WinGetcwd(a0, a1);
    80: Result := WinChdir(a0);
    81: Result := WinFchdir(a0);
    82: Result := WinRenameAt(LX_AT_FDCWD, a0, LX_AT_FDCWD, a1);   { rename }
    83: Result := WinMkdirAt(LX_AT_FDCWD, a0);                    { mkdir }
    84: Result := WinUnlinkAt(LX_AT_FDCWD, a0, $200);             { rmdir }
    87: Result := WinUnlinkAt(LX_AT_FDCWD, a0, 0);                { unlink }
    89: Result := WinReadlinkAt(LX_AT_FDCWD, a0, a1, a2);         { readlink }
    90, 91, 92, 93, 94, 95, 132, 280: Result := 0;                { chmod family, umask, utime(s): no POSIX modes }
    99: Result := WinSysinfo(a0);
    217: Result := WinGetdents(a0, a1, a2);
    295: Result := WinPrwv(a0, a1, a2, a3, False);                 { preadv }
    296: Result := WinPrwv(a0, a1, a2, a3, True);                  { pwritev }
    257: Result := WinOpenAt(a0, a1, a2, a3);                     { openat }
    258: Result := WinMkdirAt(a0, a1);
    262: Result := WinStatAt(a0, a1, a2, a3);                     { newfstatat }
    263: Result := WinUnlinkAt(a0, a1, a2);
    264, 316: Result := WinRenameAt(a0, a1, a2, a3);              { renameat, renameat2 }
    267: Result := WinReadlinkAt(a0, a1, a2, a3);
    268: Result := 0;                                             { fchmodat }
    269, 439: Result := WinAccessAt(a0, a1);                      { faccessat, faccessat2 }
    292: Result := WinDup2(a0, a1);                               { dup3 }
    293: Result := WinPipe(a0);                                   { pipe2 }
    9: Result := WinMmap(a0, a1, a2, a3);
    10: Result := WinMprotect(a0, a1, a2);
    11: Result := WinMunmap(a0);
    12: Result := WinBrk(a0);
    13, 14, 131: Result := 0;                   { rt_sigaction, rt_sigprocmask, sigaltstack }
    16: Result := -LX_ENOTTY;                   { ioctl }
    20: Result := WinWritev(a0, a1, a2);
    24: begin W_SwitchToThread; Result := 0; end;   { sched_yield }
    28: Result := 0;                            { madvise }
    35: Result := WinNanosleep(a0);
    39: Result := W_GetCurrentProcessId;        { getpid }
    60, 231: begin W_ExitProcess(a0 and $FF); Result := 0; end;   { exit, exit_group: one thread }
    63: Result := WinUname(a0);
    97: Result := WinGetrlimit(a0, a1);
    158: Result := 0;                           { arch_prctl: the block is reached rip-relative }
    186: Result := W_GetCurrentThreadId;        { gettid }
    202: Result := 0;                           { futex: one thread, nothing to wait for }
    218: Result := W_GetCurrentThreadId;        { set_tid_address }
    228: Result := WinClockGettime(a0, a1);
  else
    begin
      TraceUnmapped(nr);
      Result := -LX_ENOSYS;
    end;
  end;
end;

end.
