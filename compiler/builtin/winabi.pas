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
  LX_EINTR = 4;
  LX_EAGAIN = 11;

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
  WinMainTid: Int64;                    { the thread whose exit() ends the process }
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
function W_PeekNamedPipe(h, buf, size, read, avail, left: Int64): LongInt; cdecl; external 'kernel32.dll' name 'PeekNamedPipe';
function W_WaitForSingleObject(h, ms: Int64): LongWord; cdecl; external 'kernel32.dll' name 'WaitForSingleObject';
function W_CreateProcessW(app, cmd, pa, ta, inherit, flags, env, cwd, si, pi: Int64): LongInt; cdecl; external 'kernel32.dll' name 'CreateProcessW';
function W_GetExitCodeProcess(h, code: Int64): LongInt; cdecl; external 'kernel32.dll' name 'GetExitCodeProcess';
function W_TerminateProcess(h, code: Int64): LongInt; cdecl; external 'kernel32.dll' name 'TerminateProcess';
function W_WaitForMultipleObjects(n, hs, all, ms: Int64): LongWord; cdecl; external 'kernel32.dll' name 'WaitForMultipleObjects';
function W_AddVectoredExceptionHandler(first, handler: Int64): Int64; cdecl; external 'kernel32.dll' name 'AddVectoredExceptionHandler';
function W_SetConsoleCtrlHandler(handler, add: Int64): LongInt; cdecl; external 'kernel32.dll' name 'SetConsoleCtrlHandler';
function W_CreateThread(attr, stack, start, param, flags, tid: Int64): Int64; cdecl; external 'kernel32.dll' name 'CreateThread';
function W_ResumeThread(h: Int64): LongWord; cdecl; external 'kernel32.dll' name 'ResumeThread';
procedure W_ExitThread(code: Int64); cdecl; external 'kernel32.dll' name 'ExitThread';
procedure W_AcquireSRWLockExclusive(lock: Int64); cdecl; external 'kernel32.dll' name 'AcquireSRWLockExclusive';
procedure W_ReleaseSRWLockExclusive(lock: Int64); cdecl; external 'kernel32.dll' name 'ReleaseSRWLockExclusive';
function W_WaitOnAddress(addr, cmp, size, ms: Int64): LongInt; cdecl; external 'kernelbase.dll' name 'WaitOnAddress';
procedure W_WakeByAddressSingle(addr: Int64); cdecl; external 'kernelbase.dll' name 'WakeByAddressSingle';
procedure W_WakeByAddressAll(addr: Int64); cdecl; external 'kernelbase.dll' name 'WakeByAddressAll';
function W_GetProcessAffinityMask(proc, pmask, smask: Int64): LongInt; cdecl; external 'kernel32.dll' name 'GetProcessAffinityMask';
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
{ Every TLS access assumes the executable's PE TLS index is 0 (TlsViaTeb in
  the compiler). An EXE's always is -- the loader numbers it first -- but a
  wrong guess would be silent corruption, so it is checked once: the TLS
  directory is found through the headers at the fixed image base. }
procedure WinTlsIndexCheck;
var base, opt, rva: Int64;
begin
  base := $400000;
  opt := base + PLongInt(base + $3C)^ + 24;
  rva := PLongWord(opt + 112 + 8 * 9)^;
  if rva <> 0 then
    if PLongWord(PInt64(base + rva + 16)^)^ <> 0 then W_ExitProcess(126);
end;

function WinArgBlock: Int64;
var cmd, env, p, q, blk, ptrs, total: Int64;
    cmdLen, envLen, nEnv, nPtr, argc, n, i: Int64;
    inQ: Boolean;
begin
  WinMainTid := W_GetCurrentThreadId;
  WinTlsIndexCheck;
  ThreadRegister(WinMainTid, Int64(__pxxTlsBase));
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

{ ---- poll / select ------------------------------------------------------
  Windows has no readiness call that covers consoles, pipes and files at
  once, so readiness is decided per fd and the wait is a short sleep loop:
  a disk file, a memory file and a directory are always ready; a pipe is
  readable when PeekNamedPipe shows bytes or the writer is gone (that read
  answers end of file, as on Linux, and is reported with POLLHUP); a console
  is readable when its handle is signalled. Writes are always ready. }
const
  LX_POLLIN = 1; LX_POLLPRI = 2; LX_POLLOUT = 4; LX_POLLHUP = $10; LX_POLLNVAL = $20;

{ POLLIN, POLLIN|POLLHUP, 0 (not yet), or POLLNVAL. }
function ReadReady(fd: Int64): LongInt;
var h, avail: Int64;
    t: LongWord;
begin
  case FdKind(fd) of
    FK_NONE: begin Result := LX_POLLNVAL; Exit; end;
    FK_MEM, FK_DIR: begin Result := LX_POLLIN; Exit; end;
  end;
  h := WinFd[fd];
  t := W_GetFileType(h);
  if t = 3 then                                    { FILE_TYPE_PIPE }
  begin
    avail := 0;
    if W_PeekNamedPipe(h, 0, 0, 0, Int64(@avail), 0) = 0 then Result := LX_POLLIN or LX_POLLHUP
    else if (avail and $FFFFFFFF) > 0 then Result := LX_POLLIN
    else Result := 0;
  end
  else if t = 2 then                               { FILE_TYPE_CHAR: the console }
  begin
    if W_WaitForSingleObject(h, 0) = 0 then Result := LX_POLLIN else Result := 0;
  end
  else
    Result := LX_POLLIN;
end;

{ One pass over a pollfd array; answers how many have revents set. }
function PollPass(fds, n: Int64): Int64;
var i, fd, ev, rv, r: Int64;
begin
  Result := 0;
  for i := 0 to n - 1 do
  begin
    fd := PLongInt(fds + 8 * i)^;
    ev := PWord(fds + 8 * i + 4)^;
    rv := 0;
    if fd >= 0 then
    begin
      r := ReadReady(fd);
      if r = LX_POLLNVAL then rv := LX_POLLNVAL
      else
      begin
        if (ev and LX_POLLIN) <> 0 then rv := rv or (r and LX_POLLIN);
        rv := rv or (r and LX_POLLHUP);
        if (ev and LX_POLLOUT) <> 0 then rv := rv or LX_POLLOUT;
      end;
    end;
    PWord(fds + 8 * i + 6)^ := rv;
    if rv <> 0 then Result := Result + 1;
  end;
end;

{ ms < 0 waits for ever. }
function WinPoll(fds, n, ms: Int64): Int64;
var waited, step: Int64;
begin
  waited := 0;
  step := 1;
  while True do
  begin
    Result := PollPass(fds, n);
    if Result > 0 then Exit;
    if (ms >= 0) and (waited >= ms) then Exit;
    W_Sleep(step);
    waited := waited + step;
    if step < 10 then step := step + 1;
  end;
end;

{ select / pselect6 over fd_set bitmaps (an fd_set is 1024 bits). }
function SelPass(n, rs, ws, es: Int64; var outR, outW: array of Int64): Int64;
var fd, word, bit: Int64;
    r: LongInt;
begin
  Result := 0;
  for word := 0 to 15 do begin outR[word] := 0; outW[word] := 0; end;
  for fd := 0 to n - 1 do
  begin
    word := fd shr 6;
    bit := Int64(1) shl (fd and 63);
    if (rs <> 0) and ((PInt64(rs + 8 * word)^ and bit) <> 0) then
    begin
      r := ReadReady(fd);
      if r = LX_POLLNVAL then begin Result := -LX_EBADF; Exit; end;
      if r <> 0 then begin outR[word] := outR[word] or bit; Result := Result + 1; end;
    end;
    if (ws <> 0) and ((PInt64(ws + 8 * word)^ and bit) <> 0) then
    begin
      if FdKind(fd) = FK_NONE then begin Result := -LX_EBADF; Exit; end;
      outW[word] := outW[word] or bit;
      Result := Result + 1;
    end;
  end;
end;

function WinSelect(n, rs, ws, es, ms: Int64): Int64;
var outR, outW: array[0..15] of Int64;
    waited, step, words, i: Int64;
begin
  if n > 1024 then n := 1024;
  if n < 0 then begin Result := -LX_EINVAL; Exit; end;
  waited := 0;
  step := 1;
  while True do
  begin
    Result := SelPass(n, rs, ws, es, outR, outW);
    if Result < 0 then Exit;
    if (Result > 0) or ((ms >= 0) and (waited >= ms)) then Break;
    W_Sleep(step);
    waited := waited + step;
    if step < 10 then step := step + 1;
  end;
  words := (n + 63) shr 6;
  for i := 0 to words - 1 do
  begin
    if rs <> 0 then PInt64(rs + 8 * i)^ := outR[i];
    if ws <> 0 then PInt64(ws + 8 * i)^ := outW[i];
    if es <> 0 then PInt64(es + 8 * i)^ := 0;
  end;
end;

{ A timespec / timeval pointer as milliseconds, -1 for NULL (for ever). }
function TsMs(ts: Int64): Int64;
begin
  if ts = 0 then Result := -1
  else Result := PInt64(ts)^ * 1000 + (PInt64(ts + 8)^ + 999999) div 1000000;
end;

function TvMs(tv: Int64): Int64;
begin
  if tv = 0 then Result := -1
  else Result := PInt64(tv)^ * 1000 + (PInt64(tv + 8)^ + 999) div 1000;
end;

{ ---- Processes -------------------------------------------------------------
  Windows cannot fork, so the runtime's spawn primitive (platform_backend's
  PalBackendVforkAndExec3 under PXX_OS_WINDOWS) hands the whole request over
  in one call, WIN_PXX_SPAWN: path, argv, envp and the six fds it would have
  dup2'd. CreateProcessW starts the program with the three std handles as
  inheritable duplicates (and nothing else inheritable: CreatePipe makes
  non-inheritable ends, so the parent's copies of a pipe never keep the
  child's end open). The child's pid indexes a small table of process
  handles that wait4 and kill use. }
const
  MAX_CHILD = 64;
  LX_ECHILD = 10; LX_ESRCH = 3;
var
  ChildPid: array[0..MAX_CHILD-1] of Int64;
  ChildH: array[0..MAX_CHILD-1] of Int64;
  ChildSig: array[0..MAX_CHILD-1] of Int64;      { the signal kill() ended it with, or 0 }

{ An inheritable copy of fd's handle (0 when the fd has none). }
function InhDup(fd: Int64): Int64;
var h: Int64;
begin
  Result := 0;
  h := FdHandle(fd);
  if h = 0 then Exit;
  if W_DuplicateHandle(-1, h, -1, Int64(@Result), 0, 1, 2) = 0 then Result := 0;
end;

{ One argv string onto the UTF-8 command line at ArgOut, quoted so the
  child's C runtime (and WinArgBlock) splits it back to the same bytes. }
procedure QuoteArg(a: Int64);
var p, n, i: Int64;
    need: Boolean;
begin
  need := PByte(a)^ = 0;
  p := a;
  while PByte(p)^ <> 0 do
  begin
    if (PByte(p)^ = 32) or (PByte(p)^ = 9) or (PByte(p)^ = 34) then need := True;
    p := p + 1;
  end;
  if not need then
  begin
    p := a;
    while PByte(p)^ <> 0 do begin PutByte(PByte(p)^); p := p + 1; end;
    Exit;
  end;
  PutByte(34);
  p := a;
  while True do
  begin
    n := 0;
    while PByte(p)^ = 92 do begin n := n + 1; p := p + 1; end;
    if PByte(p)^ = 0 then
    begin
      for i := 1 to 2 * n do PutByte(92);
      Break;
    end;
    if PByte(p)^ = 34 then
    begin
      for i := 1 to 2 * n + 1 do PutByte(92);
      PutByte(34);
    end
    else
    begin
      for i := 1 to n do PutByte(92);
      PutByte(PByte(p)^);
    end;
    p := p + 1;
  end;
  PutByte(34);
end;

function WinSpawn(path, argv, envp, fds: Int64): Int64;
var u8, w, envW, size, envSize, p, q, i, n, slot, inF, outF, errF: Int64;
    si: array[0..12] of Int64;    { STARTUPINFOW, 104 bytes }
    pi: array[0..2] of Int64;     { PROCESS_INFORMATION, 24 bytes }
    appW: array[0..WPATH-1] of Word;
    hIn, hOut, hErr, app: Int64;
    ok: LongInt;
    sep: Boolean;
begin
  slot := -1;
  for i := 0 to MAX_CHILD - 1 do
    if ChildH[i] = 0 then begin slot := i; Break; end;
  if slot < 0 then begin Result := -LX_ENOMEM; Exit; end;
  { sizes: the command line and the environment, as UTF-8 then UTF-16 }
  size := 16;
  if argv <> 0 then
  begin
    i := 0;
    while PInt64(argv + 8 * i)^ <> 0 do
    begin
      p := PInt64(argv + 8 * i)^;
      n := 0;
      while PByte(p + n)^ <> 0 do n := n + 1;
      size := size + 2 * n + 3;
      i := i + 1;
    end;
  end;
  envSize := 2;
  if envp <> 0 then
  begin
    i := 0;
    while PInt64(envp + 8 * i)^ <> 0 do
    begin
      p := PInt64(envp + 8 * i)^;
      n := 0;
      while PByte(p + n)^ <> 0 do n := n + 1;
      envSize := envSize + n + 1;
      i := i + 1;
    end;
  end;
  u8 := W_VirtualAlloc(0, size + 2 * size + 2 * envSize + 64,
                       MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE);
  if u8 = 0 then begin Result := -LX_ENOMEM; Exit; end;
  w := u8 + size;
  envW := w + 2 * size;
  { the command line }
  ArgOut := u8;
  if argv <> 0 then
  begin
    i := 0;
    while PInt64(argv + 8 * i)^ <> 0 do
    begin
      if i > 0 then PutByte(32);
      QuoteArg(PInt64(argv + 8 * i)^);
      i := i + 1;
    end;
  end;
  PutByte(0);
  Utf8ToW(u8, w, size);
  { the environment block: NAME=VALUE strings, each NUL-ended, then a NUL }
  if envp <> 0 then
  begin
    q := envW;
    i := 0;
    while PInt64(envp + 8 * i)^ <> 0 do
    begin
      n := Utf8ToW(PInt64(envp + 8 * i)^, q, envSize - (q - envW) div 2);
      if n < 0 then Break;
      q := q + 2 * (n + 1);
      i := i + 1;
    end;
    PWord(q)^ := 0;
    if i = 0 then begin PWord(q + 2)^ := 0; end;
  end;
  { the program: a path is given to CreateProcessW as is; a bare name is
    left for it to search (the command line's first word) }
  sep := False;
  p := path;
  while PByte(p)^ <> 0 do
  begin
    if (PByte(p)^ = 47) or (PByte(p)^ = 92) or (PByte(p)^ = 58) then sep := True;
    p := p + 1;
  end;
  app := 0;
  if sep then
  begin
    if WinPath(LX_AT_FDCWD, path, Int64(@appW[0])) < 0 then
    begin
      W_VirtualFree(u8, 0, MEM_RELEASE);
      Result := -LX_ENOENT;
      Exit;
    end;
    app := Int64(@appW[0]);
  end;
  { std handles: the redirections PalBackendVforkAndExec3 would have made }
  inF := PLongInt(fds)^;
  outF := PLongInt(fds + 12)^;
  errF := PLongInt(fds + 20)^;
  if inF <> -1 then hIn := InhDup(inF) else hIn := InhDup(0);
  if outF <> -1 then hOut := InhDup(outF) else hOut := InhDup(1);
  if errF = -2 then                               { stderr=STDOUT: follows the stdout pipe, if any }
  begin
    if outF <> -1 then hErr := InhDup(outF) else hErr := InhDup(1);
  end
  else if errF <> -1 then hErr := InhDup(errF)
  else hErr := InhDup(2);
  for i := 0 to 12 do si[i] := 0;
  PLongWord(Int64(@si[0]))^ := 104;               { cb }
  PLongWord(Int64(@si[0]) + 60)^ := $100;         { STARTF_USESTDHANDLES }
  si[10] := hIn; si[11] := hOut; si[12] := hErr;
  pi[0] := 0; pi[1] := 0; pi[2] := 0;
  if envp <> 0 then
    ok := W_CreateProcessW(app, w, 0, 0, 1, $400, envW, 0, Int64(@si[0]), Int64(@pi[0]))   { CREATE_UNICODE_ENVIRONMENT }
  else
    ok := W_CreateProcessW(app, w, 0, 0, 1, 0, 0, 0, Int64(@si[0]), Int64(@pi[0]));
  if ok = 0 then Result := WinErr;
  if hIn <> 0 then W_CloseHandle(hIn);
  if hOut <> 0 then W_CloseHandle(hOut);
  if hErr <> 0 then W_CloseHandle(hErr);
  W_VirtualFree(u8, 0, MEM_RELEASE);
  if ok = 0 then Exit;
  W_CloseHandle(pi[1]);                           { the thread }
  ChildH[slot] := pi[0];
  ChildPid[slot] := PLongWord(Int64(@pi[0]) + 16)^;
  ChildSig[slot] := 0;
  Result := ChildPid[slot];
end;

function ChildSlot(pid: Int64): Int64;
var i: Int64;
begin
  Result := -1;
  for i := 0 to MAX_CHILD - 1 do
    if (ChildH[i] <> 0) and (ChildPid[i] = pid) then begin Result := i; Exit; end;
end;

{ wait4: one child (pid > 0) or any (-1, 0 and the group forms alike; there
  are no process groups to tell apart). WNOHANG is option bit 1. }
function WinWait4(pid, status, options, rusage: Int64): Int64;
var i, n, slot, r: Int64;
    hs: array[0..MAX_CHILD-1] of Int64;
    map: array[0..MAX_CHILD-1] of Int64;
    code: LongWord;
    ms: Int64;
begin
  if (options and 1) <> 0 then ms := 0 else ms := $FFFFFFFF;   { INFINITE }
  n := 0;
  for i := 0 to MAX_CHILD - 1 do
    if (ChildH[i] <> 0) and ((pid <= 0) or (ChildPid[i] = pid)) then
    begin
      hs[n] := ChildH[i]; map[n] := i; n := n + 1;
    end;
  if n = 0 then begin Result := -LX_ECHILD; Exit; end;
  r := W_WaitForMultipleObjects(n, Int64(@hs[0]), 0, ms);
  if r = $102 then begin Result := 0; Exit; end;              { WAIT_TIMEOUT }
  if (r < 0) or (r >= n) then begin Result := WinErr; Exit; end;
  slot := map[r];
  code := 0;
  W_GetExitCodeProcess(ChildH[slot], Int64(@code));
  if status <> 0 then
  begin
    if ChildSig[slot] <> 0 then PLongInt(status)^ := ChildSig[slot] and $7F
    else PLongInt(status)^ := (code and $FF) shl 8;
  end;
  if rusage <> 0 then
    for i := 0 to 143 do PByte(rusage + i)^ := 0;
  W_CloseHandle(ChildH[slot]);
  ChildH[slot] := 0;
  Result := ChildPid[slot];
end;

{ kill: a child of ours is terminated and reported as killed by the
  signal; signal 0 only asks whether it exists. }
function WinKill(pid, sig: Int64): Int64;
var slot: Int64;
begin
  slot := ChildSlot(pid);
  if slot < 0 then
  begin
    Result := -LX_ESRCH;
    Exit;
  end;
  if sig = 0 then begin Result := 0; Exit; end;
  if W_TerminateProcess(ChildH[slot], 128 + sig) = 0 then begin Result := WinErr; Exit; end;
  ChildSig[slot] := sig;
  Result := 0;
end;

{ ---- Calls from Windows into this program -----------------------------------
  Windows calls back with the Microsoft x64 convention (rcx, rdx, r8, r9;
  rbx, rbp, rsi, rdi, r12-r15 and xmm6-15 callee-saved), and everything pxx
  compiles is SysV. MsToSysV writes a small adapter for one SysV target into
  an executable page: save every register Windows expects back (pxx code does
  not keep rbx/r12-r15 either, so all of them), move the four arguments over,
  call, put everything back. Written as bytes at run time because the
  target's address goes in as an immediate and an `assembler` routine gets a
  frame around it. The page holds 15 adapters of 256 bytes (one is ~240);
  the last 256 bytes hold the stack-switch helpers (ThunkHelpers). }
var
  ThunkPage, ThunkUsed: Int64;

procedure TB(var p: Int64; b: Int64);
begin
  PByte(p)^ := b;
  p := p + 1;
end;

const
  THUNK_HELPERS = 15 * 256;
  H_JUMP = 0;          { (sp, target): rsp := sp; rax := 0; jmp target -- never returns }
  H_SWITCHCALL = 16;   { (sp, fn, arg): rsp := sp; fn(arg) -- never returns }
  H_LOCKOR = 32;       { (addr, bits): lock or [addr], bits }
  H_LOCKBTR = 48;      { (addr, bit): lock btr [addr], bit; the old bit }

type
  THJump = procedure(sp, target: Int64); cdecl;
  THSwitchCall = procedure(sp, fn, arg: Int64); cdecl;
  THLockOr = procedure(addr, bits: Int64); cdecl;
  THLockBtr = function(addr, bit: Int64): Int64; cdecl;

{ The page, with the helpers written the first time. False if Windows
  refused the page. }
function ThunkPageReady: Boolean;
var p: Int64;
begin
  if ThunkPage = 0 then
  begin
    ThunkPage := W_VirtualAlloc(0, 4096, MEM_RESERVE or MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    if ThunkPage <> 0 then
    begin
      p := ThunkPage + THUNK_HELPERS + H_JUMP;
      TB(p, $48); TB(p, $89); TB(p, $FC);      { mov rsp, rdi }
      TB(p, $31); TB(p, $C0);                  { xor eax, eax }
      TB(p, $FF); TB(p, $E6);                  { jmp rsi }
      p := ThunkPage + THUNK_HELPERS + H_SWITCHCALL;
      TB(p, $48); TB(p, $89); TB(p, $FC);      { mov rsp, rdi }
      TB(p, $48); TB(p, $89); TB(p, $D7);      { mov rdi, rdx }
      TB(p, $FF); TB(p, $D6);                  { call rsi }
      TB(p, $0F); TB(p, $0B);                  { ud2 }
      p := ThunkPage + THUNK_HELPERS + H_LOCKOR;
      TB(p, $F0); TB(p, $48); TB(p, $09); TB(p, $37);   { lock or [rdi], rsi }
      TB(p, $C3);
      p := ThunkPage + THUNK_HELPERS + H_LOCKBTR;
      TB(p, $F0); TB(p, $48); TB(p, $0F); TB(p, $B3); TB(p, $37);   { lock btr [rdi], rsi }
      TB(p, $0F); TB(p, $92); TB(p, $C0);      { setc al }
      TB(p, $0F); TB(p, $B6); TB(p, $C0);      { movzx eax, al }
      TB(p, $C3);
    end;
  end;
  Result := ThunkPage <> 0;
end;

procedure TD(var p: Int64; d: Int64);
begin
  PLongWord(p)^ := d and $FFFFFFFF;
  p := p + 4;
end;

{ movups [rsp+disp32], xmmN (store) or movups xmmN, [rsp+disp32] (load). }
procedure TXmm(var p: Int64; n, disp: Int64; load: Boolean);
begin
  if n >= 8 then TB(p, $44);
  TB(p, $0F);
  if load then TB(p, $10) else TB(p, $11);
  TB(p, $84 or ((n and 7) shl 3));     { mod=10 reg=n rm=100 }
  TB(p, $24);                          { SIB: base rsp }
  TD(p, disp);
end;

procedure LockOr(addr, bits: Int64);
begin
  if ThunkPageReady then THLockOr(ThunkPage + THUNK_HELPERS + H_LOCKOR)(addr, bits);
end;

function LockBtr(addr, bit: Int64): Boolean;
begin
  Result := False;
  if ThunkPageReady then
    Result := THLockBtr(ThunkPage + THUNK_HELPERS + H_LOCKBTR)(addr, bit) <> 0;
end;

function MsToSysV(target: Int64): Int64;
var p, i: Int64;
begin
  Result := 0;
  if not ThunkPageReady then Exit;
  if ThunkUsed >= 15 then Exit;
  p := ThunkPage + 256 * ThunkUsed;
  Result := p;
  ThunkUsed := ThunkUsed + 1;
  TB(p, $55);                                        { push rbp      (rsp = 0 mod 16) }
  TB(p, $48); TB(p, $89); TB(p, $E5);                { mov rbp, rsp }
  TB(p, $56); TB(p, $57); TB(p, $53);                { push rsi; push rdi; push rbx }
  TB(p, $41); TB(p, $54); TB(p, $41); TB(p, $55);    { push r12; push r13 }
  TB(p, $41); TB(p, $56); TB(p, $41); TB(p, $57);    { push r14; push r15 (8 mod 16) }
  TB(p, $48); TB(p, $81); TB(p, $EC); TD(p, 168);    { sub rsp, 168  (0 mod 16) }
  for i := 6 to 15 do TXmm(p, i, 16 * (i - 6), False);
  TB(p, $48); TB(p, $89); TB(p, $CF);                { mov rdi, rcx }
  TB(p, $48); TB(p, $89); TB(p, $D6);                { mov rsi, rdx }
  TB(p, $4C); TB(p, $89); TB(p, $C2);                { mov rdx, r8 }
  TB(p, $4C); TB(p, $89); TB(p, $C9);                { mov rcx, r9 }
  TB(p, $48); TB(p, $B8);                            { mov rax, imm64 }
  TD(p, target); TD(p, target shr 32);
  TB(p, $FF); TB(p, $D0);                            { call rax }
  for i := 6 to 15 do TXmm(p, i, 16 * (i - 6), True);
  TB(p, $48); TB(p, $81); TB(p, $C4); TD(p, 168);    { add rsp, 168 }
  TB(p, $41); TB(p, $5F); TB(p, $41); TB(p, $5E);    { pop r15; pop r14 }
  TB(p, $41); TB(p, $5D); TB(p, $41); TB(p, $5C);    { pop r13; pop r12 }
  TB(p, $5B); TB(p, $5F); TB(p, $5E); TB(p, $5D);    { pop rbx; pop rdi; pop rsi; pop rbp }
  TB(p, $C3);                                        { ret }
end;

{ ---- Threads -------------------------------------------------------------------
  The clone stub (thread_emit.inc) carves the child's stack, TLS block and
  stage area exactly as on Linux and calls clone with the address to resume
  the child at in r9, as for the BSDs. WinClone records what the child needs
  just below the stage area (on the child's own stack, which nothing uses
  before it runs), starts a suspended thread at WinThreadStart, stores the
  tid for CLONE_PARENT_SETTID, and resumes it.

  WinThreadStart runs on the Windows stack CreateThread gave it. Its TLS
  block is the loader's (zeroed); it seeds the init-image slot from the
  parent's, keeps a spot on this Windows stack and the CLEARTID word in the
  block's 16-byte scratch, and jumps to the stub's child leg on the pxx
  stack. The stub's arch_prctl(SET_GS, staged block) then copies the staged
  block into the loader's (WinSetBlock).

  exit() on such a thread goes back to the Windows stack first, because the
  joiner frees the pxx stack once the CLEARTID word is 0 -- the order the
  kernel keeps on Linux -- then clears the word, wakes the joiner, and ends
  the thread. }
var
  WinStartThunk: Int64;
  WinLock: Int64;               { an SRWLOCK, around the fd table, brk and spawn }

{ Past each thread's block, in its 32-byte scratch: the saved Windows stack
  (+0), the CLEARTID word (+8), the blocked-signal mask (+16) and the
  signals sent to this thread alone (+24). The main thread's +0/+8 hold
  getrlimit's answer from startup, which nothing reads after. }
function ThreadWord(off: Int64): Int64;
begin
  Result := Int64(__pxxTlsBase) + __pxxTlsBlockSize + off;
end;

const
  TW_SP = 0; TW_CTID = 8; TW_BLOCKED = 16; TW_PENDING = 24;
  MAX_THREAD = 256;

var
  ThreadTid, ThreadBlk: array[0..MAX_THREAD-1] of Int64;   { for tkill to another thread }

procedure ThreadRegister(tid, blk: Int64);
var i: Integer;
begin
  W_AcquireSRWLockExclusive(Int64(@WinLock));
  for i := 0 to MAX_THREAD - 1 do
    if ThreadTid[i] = 0 then
    begin
      ThreadBlk[i] := blk;
      ThreadTid[i] := tid;
      Break;
    end;
  W_ReleaseSRWLockExclusive(Int64(@WinLock));
end;

procedure ThreadUnregister(tid: Int64);
var i: Integer;
begin
  W_AcquireSRWLockExclusive(Int64(@WinLock));
  for i := 0 to MAX_THREAD - 1 do
    if ThreadTid[i] = tid then begin ThreadTid[i] := 0; Break; end;
  W_ReleaseSRWLockExclusive(Int64(@WinLock));
end;

{ The scratch of thread `tid', or 0. }
function ThreadScratch(tid: Int64): Int64;
var i: Integer;
begin
  Result := 0;
  W_AcquireSRWLockExclusive(Int64(@WinLock));
  for i := 0 to MAX_THREAD - 1 do
    if ThreadTid[i] = tid then begin Result := ThreadBlk[i] + __pxxTlsBlockSize; Break; end;
  W_ReleaseSRWLockExclusive(Int64(@WinLock));
end;

function WinSetBlock(blk: Int64): Int64;
var dst, i: Int64;
begin
  dst := Int64(__pxxTlsBase);
  if blk <> dst then
    for i := 0 to __pxxTlsBlockSize div 8 - 1 do
      PInt64(dst + 8 * i)^ := PInt64(blk + 8 * i)^;
  PInt64(dst)^ := dst;                         { slot 0 = self }
  Result := 0;
end;

function WinThreadStart(stage: Int64): Int64; cdecl;
var blk, mark: Int64;
begin
  blk := Int64(__pxxTlsBase);
{$ifdef PXX_HAS_TLS_INIT_IMAGE}
  PInt64(blk + __pxxTlsInitImageSlotOff)^ := PInt64(stage - 32)^;
{$endif}
  PInt64(blk + __pxxTlsBlockSize + TW_SP)^ := (Int64(@mark) - 512) and not Int64(15);
  PInt64(blk + __pxxTlsBlockSize + TW_CTID)^ := PInt64(stage - 24)^;
  PInt64(blk + __pxxTlsBlockSize + TW_BLOCKED)^ := PInt64(stage - 40)^;   { the mask is inherited }
  ThreadRegister(W_GetCurrentThreadId, blk);
  THJump(ThunkPage + THUNK_HELPERS + H_JUMP)(stage, PInt64(stage - 16)^);
  Result := 0;
end;

procedure WinThreadFinal(ctid: Int64); cdecl;
begin
  ThreadUnregister(W_GetCurrentThreadId);
  if ctid <> 0 then
  begin
    PLongInt(ctid)^ := 0;
    W_WakeByAddressAll(ctid);
  end;
  W_ExitThread(0);
end;

{ exit() of one thread. The main thread's ends the process, as winabi did
  before threads; a thread Windows started (no saved stack) just ends. }
procedure WinThreadExit(code: Int64);
var blk, sp: Int64;
begin
  if W_GetCurrentThreadId = WinMainTid then W_ExitProcess(code and $FF);
  blk := Int64(__pxxTlsBase);
  sp := PInt64(blk + __pxxTlsBlockSize + TW_SP)^;
  if sp = 0 then W_ExitThread(code);
  THSwitchCall(ThunkPage + THUNK_HELPERS + H_SWITCHCALL)(sp, Int64(@WinThreadFinal),
    PInt64(blk + __pxxTlsBlockSize + TW_CTID)^);
end;

function WinClone(flags, stack, ptid, ctid, cont: Int64): Int64;
var h: Int64;
    tid: LongWord;
begin
  if ((flags and $100) = 0) or (stack = 0) or (cont = 0) then
  begin
    Result := -LX_EINVAL; Exit;                { only CLONE_VM threads }
  end;
  if WinStartThunk = 0 then WinStartThunk := MsToSysV(Int64(@WinThreadStart));
  if WinStartThunk = 0 then begin Result := -LX_ENOMEM; Exit; end;
  PInt64(stack - 16)^ := cont;
  if (flags and $200000) <> 0 then PInt64(stack - 24)^ := ctid   { CLONE_CHILD_CLEARTID }
  else PInt64(stack - 24)^ := 0;
  PInt64(stack - 32)^ := 0;
  PInt64(stack - 40)^ := PInt64(ThreadWord(TW_BLOCKED))^;
{$ifdef PXX_HAS_TLS_INIT_IMAGE}
  PInt64(stack - 32)^ := PInt64(Int64(__pxxTlsBase) + __pxxTlsInitImageSlotOff)^;
{$endif}
  tid := 0;
  h := W_CreateThread(0, 256 * 1024, WinStartThunk, stack, 4, Int64(@tid));   { CREATE_SUSPENDED }
  if h = 0 then begin Result := WinErr; Exit; end;
  if ((flags and $100000) <> 0) and (ptid <> 0) then PLongInt(ptid)^ := tid;     { CLONE_PARENT_SETTID }
  if ((flags and $1000000) <> 0) and (ctid <> 0) then PLongInt(ctid)^ := tid;    { CLONE_CHILD_SETTID }
  W_ResumeThread(h);
  W_CloseHandle(h);
  Result := tid;
end;

{ sched_getaffinity(pid, size, mask): the process's affinity mask (the first
  64 CPUs; one processor group). Linux answers with its mask's size. }
function WinGetaffinity(size, mask: Int64): Int64;
var pm, sm: Int64;
begin
  if size < 8 then begin Result := -LX_EINVAL; Exit; end;
  pm := 0; sm := 0;
  if W_GetProcessAffinityMask(-1, Int64(@pm), Int64(@sm)) = 0 then pm := 1;
  PInt64(mask)^ := pm;
  Result := 8;
end;

{ futex: WAIT and WAKE (and their BITSET forms, as plain ones) over
  WaitOnAddress. A wake reports 0 woken: Windows does not say. }
function WinFutex(uaddr, op, val, ts: Int64): Int64;
var cmd, ms: Int64;
    cmp: LongInt;
    now: array[0..1] of Int64;
begin
  cmd := op and 127;
  case cmd of
    0, 9:
      begin
        if PLongInt(uaddr)^ <> LongInt(val) then begin Result := -LX_EAGAIN; Exit; end;
        if ts = 0 then ms := $FFFFFFFF
        else if cmd = 0 then ms := TsMs(ts)
        else
        begin
          if (op and 256) <> 0 then WinClockGettime(0, Int64(@now[0]))   { FUTEX_CLOCK_REALTIME }
          else WinClockGettime(1, Int64(@now[0]));
          ms := (PInt64(ts)^ - now[0]) * 1000 + (PInt64(ts + 8)^ - now[1]) div 1000000;
          if ms <= 0 then begin Result := -110; Exit; end;               { ETIMEDOUT }
        end;
        cmp := LongInt(val);
        if W_WaitOnAddress(uaddr, Int64(@cmp), 4, ms) = 0 then
        begin
          if W_GetLastError = 1460 then begin Result := -110; Exit; end;  { ERROR_TIMEOUT }
        end;
        Result := 0;
      end;
    1, 10:
      begin
        if val = 1 then W_WakeByAddressSingle(uaddr) else W_WakeByAddressAll(uaddr);
        Result := 0;
      end;
  else
    Result := -LX_ENOSYS;
  end;
end;

{ ---- Signals: hardware faults -------------------------------------------------
  rt_sigaction records the program's handler (the compiler's fault-to-raise
  stub, Linux SA_SIGINFO ABI) per Linux signal number. For the fault signals
  a vectored exception handler is installed once; it turns the Windows
  exception into the Linux signal, builds a Linux siginfo/ucontext from the
  Windows CONTEXT (fpregs points at the CONTEXT's FltSave, which is the same
  fxsave layout), calls the handler, copies the register file back, and
  continues there -- the handler rewrites RIP/RSP to raise the exception, as
  on Linux. An exception with no handler for its signal is left to Windows.
  Asynchronous signals (Ctrl-C) are not here yet. }
const
  { Linux gregs[0..17] (R8..R15 RDI RSI RBP RBX RDX RAX RCX RSP RIP EFL)
    -> offset in the Windows x64 CONTEXT. }
  WinGregOff: array[0..17] of Integer = (
    $B8, $C0, $C8, $D0, $D8, $E0, $E8, $F0, $B0, $A8, $A0, $90, $88, $78, $80, $98, $F8, $44);
  LX_UC_GREGS = 40;
  LX_UC_FPREGS = 40 + 23 * 8;
  CTX_FLTSAVE = $100;
  CTX_MXCSR = $34;

  SIGBIT_UNBLOCKABLE = (1 shl 8) or (1 shl 18);     { SIGKILL, SIGSTOP }
  LX_SI_USER = 0;
  LX_SI_TKILL = -6;

var
  WinSigHandler: array[0..64] of Int64;
  WinSigFlags: array[0..64] of Int64;
  WinSigMask: array[0..64] of Int64;
  WinSigPending, WinSigHandled: Int64;   { WinSigPending: sent to the process }
  WinVehInstalled, WinCtrlInstalled: Boolean;

type
  TLxHandler = procedure(sig, info, uc: Int64); cdecl;

function SigBit(sig: Int64): Int64;
begin
  Result := Int64(1) shl (sig - 1);
end;

{ The lowest signal of `want' taken off the pending set at `addr', or 0.
  Atomic: another thread may be setting bits, or taking the same one. }
function WinTakeFrom(addr, want: Int64): Int64;
var sig: Int64;
begin
  Result := 0;
  for sig := 1 to 64 do
    if (PInt64(addr)^ and want and SigBit(sig)) <> 0 then
      if LockBtr(addr, sig - 1) then
      begin
        Result := sig;
        Exit;
      end;
end;

{ This thread's own pending signals first, then the process's. }
function WinTakePendingRaw(want: Int64): Int64;
begin
  Result := WinTakeFrom(ThreadWord(TW_PENDING), want);
  if Result = 0 then Result := WinTakeFrom(Int64(@WinSigPending), want);
end;

function SigBlocked: Int64;
begin
  Result := PInt64(ThreadWord(TW_BLOCKED))^;
end;

procedure SetSigBlocked(v: Int64);
begin
  PInt64(ThreadWord(TW_BLOCKED))^ := v;
end;

{ ---- Signals sent in software ------------------------------------------------
  kill/tkill/tgkill, and Ctrl-C. The mask is per thread (inherited by a new
  thread); a signal sent to the process or to this thread runs its
  disposition now unless this thread blocks it, in which case it goes on the
  process's or the thread's pending set. A signal sent to ANOTHER thread
  goes on that thread's pending set, and that thread runs it when it next
  unblocks it or finishes a syscall: Windows cannot interrupt a thread with
  a handler the way a kernel signal does, so a thread spinning without
  syscalls, or blocked in one, sees it late. A handler gets a Linux siginfo (SI_USER or SI_TKILL, our
  pid) and a ucontext whose registers are zero -- there is no interrupted
  instruction to resume or rewrite, the handler just returns to the caller.
  The default action ends the process with 128 + sig, except for the
  signals Linux ignores by default. }
procedure WinAct(sig, code: Int64);
var h, old, i: Int64;
    li: array[0..15] of Int64;        { siginfo_t }
    lu: array[0..63] of Int64;        { ucontext_t through uc_sigmask }
    fx: array[0..65] of Int64;        { fxsave area, 16-aligned inside }
begin
  h := WinSigHandler[sig];
  if h = 1 then Exit;                          { SIG_IGN }
  if h = 0 then
  begin
    case sig of
      17, 18, 20, 21, 22, 23, 28: Exit;        { CHLD CONT TSTP TTIN TTOU URG WINCH }
    else
      W_ExitProcess(128 + sig);
    end;
  end;
  for i := 0 to 15 do li[i] := 0;
  for i := 0 to 63 do lu[i] := 0;
  for i := 0 to 65 do fx[i] := 0;
  PLongInt(@li[0])^ := sig;
  PLongInt(Int64(@li[0]) + 8)^ := code;
  PLongInt(Int64(@li[0]) + 16)^ := W_GetCurrentProcessId;
  i := (Int64(@fx[0]) + 15) and not 15;
  PWord(i)^ := $37F;                           { FCW }
  PLongWord(i + $18)^ := $1F80;                { MXCSR }
  lu[LX_UC_FPREGS div 8] := i;
  old := SigBlocked;
  lu[LX_UC_FPREGS div 8 + 9] := old;           { uc_sigmask, offset 296 }
  if (WinSigFlags[sig] and $40000000) = 0 then  { not SA_NODEFER }
    SetSigBlocked(old or SigBit(sig));
  SetSigBlocked((SigBlocked or WinSigMask[sig]) and not SIGBIT_UNBLOCKABLE);
  if (WinSigFlags[sig] and $80000000) <> 0 then WinSigHandler[sig] := 0;   { SA_RESETHAND }
  TLxHandler(h)(sig, Int64(@li[0]), Int64(@lu[0]));
  WinSigHandled := WinSigHandled + 1;
  SetSigBlocked(old);
end;

procedure WinRunPending;
var sig: Int64;
begin
  repeat
    sig := WinTakePendingRaw(not SigBlocked);
    if sig <> 0 then WinAct(sig, LX_SI_USER);
  until sig = 0;
end;

function WinSignalSelf(sig, code: Int64): Int64;
begin
  if (sig < 0) or (sig > 64) then begin Result := -LX_EINVAL; Exit; end;
  Result := 0;
  if sig = 0 then Exit;
  if (SigBlocked and SigBit(sig)) <> 0 then
  begin
    if code = LX_SI_TKILL then LockOr(ThreadWord(TW_PENDING), SigBit(sig))
    else LockOr(Int64(@WinSigPending), SigBit(sig));
  end
  else
  begin
    WinAct(sig, code);
    WinRunPending;
  end;
end;

{ tkill/tgkill: to this thread, or onto another one's pending set. }
function WinSignalThread(tid, sig: Int64): Int64;
var sc: Int64;
begin
  if tid = W_GetCurrentThreadId then begin Result := WinSignalSelf(sig, LX_SI_TKILL); Exit; end;
  if (sig < 0) or (sig > 64) then begin Result := -LX_EINVAL; Exit; end;
  sc := ThreadScratch(tid);
  if sc = 0 then begin Result := -LX_ESRCH; Exit; end;
  if sig <> 0 then LockOr(sc + TW_PENDING, SigBit(sig));
  Result := 0;
end;

{ The console control handler (Microsoft ABI through MsToSysV, on a thread
  Windows starts for it): Ctrl-C is SIGINT, Ctrl-Break SIGQUIT, closing the
  console SIGHUP. TRUE says handled. }
function WinCtrl(ev: Int64): Int64; cdecl;
var sig: Int64;
begin
  case ev of
    0: sig := 2;
    1: sig := 3;
    2: sig := 1;
  else
    begin Result := 0; Exit; end;
  end;
  WinSignalSelf(sig, 128);                     { SI_KERNEL }
  Result := 1;
end;

{ The vectored handler, SysV side (MsToSysV adapts it). EXCEPTION_POINTERS:
  the record, then the CONTEXT. -1 continues, 0 passes it on. }
function WinVeh(ep: Int64): Int64; cdecl;
var rec, ctx, code, sig, sc, addr, h, trap, err, i: Int64;
    li: array[0..15] of Int64;        { Linux siginfo_t, 128 B }
    lu: array[0..63] of Int64;        { Linux ucontext_t through uc_sigmask }
begin
  Result := 0;
  rec := PInt64(ep)^;
  ctx := PInt64(ep + 8)^;
  code := PLongWord(rec)^;
  addr := PInt64(rec + $10)^;                 { ExceptionAddress }
  sc := 0; trap := 0; err := 0;
  case code of
    $C0000005, $C0000006:                     { access violation, in-page error }
      begin
        sig := 11; trap := 14;
        if PLongWord(rec + $18)^ >= 2 then
        begin
          if PInt64(rec + $20)^ = 1 then err := 6 else err := 4;   { user, write/read }
          addr := PInt64(rec + $28)^;
        end;
        sc := 1;                              { SEGV_MAPERR }
      end;
    $C00000FD: begin sig := 11; trap := 14; sc := 1; addr := PInt64(ctx + $98)^; end;   { stack overflow }
    $C0000094: begin sig := 8; sc := 1; end;  { integer divide by zero: FPE_INTDIV }
    $C0000095: begin sig := 8; sc := 2; end;  { integer overflow: FPE_INTOVF }
    $C000008E: begin sig := 8; sc := 3; end;  { FPE_FLTDIV }
    $C0000091: begin sig := 8; sc := 4; end;  { FPE_FLTOVF }
    $C0000093: begin sig := 8; sc := 5; end;  { FPE_FLTUND }
    $C000008F: begin sig := 8; sc := 6; end;  { FPE_FLTRES }
    $C0000090, $C000008D, $C00002B4, $C00002B5: begin sig := 8; sc := 7; end;   { FPE_FLTINV }
    $C000001D: begin sig := 4; sc := 1; trap := 6; end;   { illegal instruction: ILL_ILLOPC }
    $C0000096: begin sig := 11; sc := 128; trap := 13; addr := 0; end;   { privileged: SIGSEGV, SI_KERNEL }
    $80000002: begin sig := 7; sc := 1; end;  { misalignment: SIGBUS BUS_ADRALN }
    $80000003, $80000004: begin sig := 5; sc := 1; end;   { breakpoint, single step: SIGTRAP }
  else
    Exit;
  end;
  h := WinSigHandler[sig];
  { No handler: the process ends as Linux reports a fatal signal to a shell,
    128 + sig, rather than with Windows' exception code and a crash dialog
    (or, under Wine, a debugger). SIG_IGN on a fault would re-fault for ever
    on Linux; it ends the same way here. }
  if (h = 0) or (h = 1) then W_ExitProcess(128 + sig);
  for i := 0 to 15 do li[i] := 0;
  for i := 0 to 63 do lu[i] := 0;
  PLongInt(@li[0])^ := sig;
  PLongInt(Int64(@li[0]) + 8)^ := sc;
  li[2] := addr;                              { si_addr }
  for i := 0 to 16 do
    lu[LX_UC_GREGS div 8 + i] := PInt64(ctx + WinGregOff[i])^;
  lu[LX_UC_GREGS div 8 + 17] := PLongWord(ctx + WinGregOff[17])^;   { EFL is 32-bit there }
  lu[LX_UC_GREGS div 8 + 19] := err;
  lu[LX_UC_GREGS div 8 + 20] := trap;
  if sig = 11 then lu[LX_UC_GREGS div 8 + 22] := addr;              { CR2 }
  lu[LX_UC_FPREGS div 8] := ctx + CTX_FLTSAVE;
  if (WinSigFlags[sig] and $80000000) <> 0 then                    { SA_RESETHAND }
    WinSigHandler[sig] := 0;
  TLxHandler(h)(sig, Int64(@li[0]), Int64(@lu[0]));
  for i := 0 to 16 do
    PInt64(ctx + WinGregOff[i])^ := lu[LX_UC_GREGS div 8 + i];
  PLongWord(ctx + WinGregOff[17])^ := lu[LX_UC_GREGS div 8 + 17] and $FFFFFFFF;
  PLongWord(ctx + CTX_MXCSR)^ := PLongWord(ctx + CTX_FLTSAVE + $18)^;   { fxsave's MXCSR }
  Result := -1;                               { EXCEPTION_CONTINUE_EXECUTION }
end;

{ rt_sigaction: Linux struct sigaction is handler, flags, restorer, mask. }
function WinRtSigaction(sig, act, oact: Int64): Int64;
var t: Int64;
begin
  if (sig < 1) or (sig > 64) or (sig = 9) or (sig = 19) then begin Result := -LX_EINVAL; Exit; end;
  if oact <> 0 then
  begin
    PInt64(oact)^ := WinSigHandler[sig];
    PInt64(oact + 8)^ := WinSigFlags[sig];
    PInt64(oact + 16)^ := 0;
    PInt64(oact + 24)^ := WinSigMask[sig];
  end;
  if act <> 0 then
  begin
    WinSigHandler[sig] := PInt64(act)^;
    WinSigFlags[sig] := PInt64(act + 8)^;
    WinSigMask[sig] := PInt64(act + 24)^;
    if (not WinVehInstalled) and (WinSigHandler[sig] > 1) and
       ((sig = 4) or (sig = 5) or (sig = 7) or (sig = 8) or (sig = 11)) then
    begin
      t := MsToSysV(Int64(@WinVeh));
      if t <> 0 then
        if W_AddVectoredExceptionHandler(1, t) <> 0 then WinVehInstalled := True;
    end;
    if (not WinCtrlInstalled) and (WinSigHandler[sig] <> 0) and
       ((sig = 1) or (sig = 2) or (sig = 3)) then
    begin
      t := MsToSysV(Int64(@WinCtrl));
      if t <> 0 then
        if W_SetConsoleCtrlHandler(t, 1) <> 0 then WinCtrlInstalled := True;
    end;
  end;
  Result := 0;
end;

{ rt_sigprocmask(how, set, oset, size). SIGKILL and SIGSTOP cannot be
  blocked. Unblocking runs whatever was pending, lowest number first. }
function WinSigprocmask(how, setp, oset: Int64): Int64;
var v: Int64;
begin
  if oset <> 0 then PInt64(oset)^ := SigBlocked;
  if setp <> 0 then
  begin
    v := PInt64(setp)^;
    case how of
      0: v := SigBlocked or v;
      1: v := SigBlocked and not v;
      2: ;
    else
      begin Result := -LX_EINVAL; Exit; end;
    end;
    SetSigBlocked(v and not SIGBIT_UNBLOCKABLE);
    WinRunPending;
  end;
  Result := 0;
end;

{ The lowest pending signal in `want', taken off the pending set, or 0. }
function WinTakePending(want: Int64): Int64;
begin
  Result := WinTakePendingRaw(want);
end;

{ rt_sigtimedwait(set, info, timeout, size): collect a pending signal from
  `set' without running its handler. Only Ctrl-C arrives from outside, so
  the wait is a sleep loop. }
function WinSigtimedwait(setp, info, ts: Int64): Int64;
var want, ms, i: Int64;
begin
  want := PInt64(setp)^;
  ms := TsMs(ts);
  repeat
    Result := WinTakePending(want);
    if Result <> 0 then
    begin
      if info <> 0 then
      begin
        for i := 0 to 127 do PByte(info + i)^ := 0;
        PLongInt(info)^ := Result;
        PLongInt(info + 16)^ := W_GetCurrentProcessId;
      end;
      Exit;
    end;
    if ms = 0 then begin Result := -LX_EAGAIN; Exit; end;
    if ms > 0 then
    begin
      if ms < 10 then begin W_Sleep(ms); ms := 0; end
      else begin W_Sleep(10); ms := ms - 10; end;
    end
    else W_Sleep(10);
  until False;
end;

{ rt_sigsuspend(mask, size) and pause: wait with `mask' (or the current
  mask) until some signal has been handled, then EINTR. }
function WinSigsuspend(maskp: Int64): Int64;
var old, n: Int64;
begin
  old := SigBlocked;
  if maskp <> 0 then SetSigBlocked(PInt64(maskp)^ and not SIGBIT_UNBLOCKABLE);
  n := WinSigHandled;
  WinRunPending;
  while WinSigHandled = n do
  begin
    W_Sleep(10);
    WinRunPending;
  end;
  SetSigBlocked(old);
  Result := -LX_EINTR;
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

function WinSys(nr, a0, a1, a2, a3, a4, a5: Int64): Int64;
begin
  case nr of
    $7F000002: Result := WinArgBlock;             { WIN_PXX_ARGBLOCK: the entry stub }
    $7F000003: Result := WinSpawn(a0, a1, a2, a3);   { WIN_PXX_SPAWN: PalBackendVforkAndExec3 }
    57, 58: Result := -LX_ENOSYS;                    { fork, vfork: Windows cannot }
    61: Result := WinWait4(a0, a1, a2, a3);
    62: if (a0 = W_GetCurrentProcessId) or (a0 = 0) then Result := WinSignalSelf(a1, LX_SI_USER)
        else Result := WinKill(a0, a1);
    200: Result := WinSignalThread(a0, a1);                     { tkill }
    234: Result := WinSignalThread(a1, a2);                     { tgkill }
    14: Result := WinSigprocmask(a0, a1, a2);
    127: begin                                                  { rt_sigpending }
           PInt64(a0)^ := (WinSigPending or PInt64(ThreadWord(TW_PENDING))^) and SigBlocked;
           Result := 0;
         end;
    128: Result := WinSigtimedwait(a0, a1, a2);
    130: Result := WinSigsuspend(a0);
    34: Result := WinSigsuspend(0);                                 { pause }
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
    13: Result := WinRtSigaction(a0, a1, a2);
    131: Result := 0;                           { sigaltstack: faults run on the faulting stack }
    16: Result := -LX_ENOTTY;                   { ioctl }
    7: Result := WinPoll(a0, a1, a2);                             { poll }
    20: Result := WinWritev(a0, a1, a2);
    23: Result := WinSelect(a0, a1, a2, a3, TvMs(a4));             { select }
    270: Result := WinSelect(a0, a1, a2, a3, TsMs(a4));            { pselect6 }
    271: Result := WinPoll(a0, a1, TsMs(a2));                      { ppoll }
    24: begin W_SwitchToThread; Result := 0; end;   { sched_yield }
    28: Result := 0;                            { madvise }
    35: Result := WinNanosleep(a0);
    39: Result := W_GetCurrentProcessId;        { getpid }
    60: begin WinThreadExit(a0); Result := 0; end;
    231: begin W_ExitProcess(a0 and $FF); Result := 0; end;      { exit_group }
    56: Result := WinClone(a0, a1, a2, a3, a5);                   { clone: r9 = the child's resume address }
    63: Result := WinUname(a0);
    97: Result := WinGetrlimit(a0, a1);
    158: if (a0 = $1001) or (a0 = $1002) then Result := WinSetBlock(a1)   { arch_prctl SET_GS/SET_FS }
         else Result := -LX_EINVAL;
    186: Result := W_GetCurrentThreadId;        { gettid }
    202: Result := WinFutex(a0, a1, a2, a3);
    204: Result := WinGetaffinity(a1, a2);                      { sched_getaffinity }
    218: Result := W_GetCurrentThreadId;        { set_tid_address }
    228: Result := WinClockGettime(a0, a1);
  else
    begin
      TraceUnmapped(nr);
      Result := -LX_ENOSYS;
    end;
  end;
end;

{ The syscalls that change the translator's own tables (the fd table, brk,
  the child table) run one at a time; the blocking ones (read, wait4, poll,
  futex) are not among them. }
function PXXWinSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;
begin
  case nr of
    2, 3, 12, 22, 32, 33, 72, 257, 292, 293, $7F000003:
      begin
        W_AcquireSRWLockExclusive(Int64(@WinLock));
        Result := WinSys(nr, a0, a1, a2, a3, a4, a5);
        W_ReleaseSRWLockExclusive(Int64(@WinLock));
      end;
  else
    Result := WinSys(nr, a0, a1, a2, a3, a4, a5);
  end;
  { A signal another thread sent this one, or one sent to the process that
    this thread does not block: run it now, on the way out. }
  if ((WinSigPending or PInt64(ThreadWord(TW_PENDING))^) and not SigBlocked) <> 0 then
    WinRunPending;
end;

end.
