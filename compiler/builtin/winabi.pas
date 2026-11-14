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
  WinFd: array[0..MAX_FD-1] of Int64;   { Linux fd -> HANDLE; 0 = not open }
  WinFdReady: Boolean;
  WinBrkBase, WinBrkCur, WinBrkTop: Int64;
  WinTrace: LongInt;                    { 0 = not asked yet, 1 = off, 2 = on }

procedure WinFdInit;
begin
  if WinFdReady then Exit;
  WinFd[0] := W_GetStdHandle(STD_INPUT_HANDLE);
  WinFd[1] := W_GetStdHandle(STD_OUTPUT_HANDLE);
  WinFd[2] := W_GetStdHandle(STD_ERROR_HANDLE);
  WinFdReady := True;
end;

function FdHandle(fd: Int64): Int64;
begin
  WinFdInit;
  if (fd < 0) or (fd >= MAX_FD) then Result := 0
  else Result := WinFd[fd];
end;

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

function WinWrite(fd, buf, n: Int64): Int64;
var h: Int64;
    done: LongWord;
begin
  h := FdHandle(fd);
  if h = 0 then begin Result := -LX_EBADF; Exit; end;
  if n > $7FFFFFFF then n := $7FFFFFFF;
  done := 0;
  if W_WriteFile(h, buf, n, Int64(@done), 0) = 0 then Result := -LX_EIO
  else Result := done;
end;

function WinRead(fd, buf, n: Int64): Int64;
var h: Int64;
    done: LongWord;
begin
  h := FdHandle(fd);
  if h = 0 then begin Result := -LX_EBADF; Exit; end;
  if n > $7FFFFFFF then n := $7FFFFFFF;
  done := 0;
  { A broken pipe or closed console reads as end of file, as on Linux. }
  if W_ReadFile(h, buf, n, Int64(@done), 0) = 0 then Result := 0
  else Result := done;
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

function WinClose(fd: Int64): Int64;
begin
  if FdHandle(fd) = 0 then begin Result := -LX_EBADF; Exit; end;
  if fd > 2 then W_CloseHandle(WinFd[fd]);
  WinFd[fd] := 0;
  Result := 0;
end;

{ fstat: the standard handles only, as a character device (console) or a
  FIFO (pipe) or a regular file, so isatty-style checks and buffering
  decisions see what they would on Linux. Linux x86-64 struct stat: st_mode
  at 24, 144 bytes. }
function WinFstat(fd, st: Int64): Int64;
var h: Int64;
    i: Integer;
    t: LongWord;
begin
  h := FdHandle(fd);
  if h = 0 then begin Result := -LX_EBADF; Exit; end;
  for i := 0 to 143 do PByte(st + i)^ := 0;
  t := W_GetFileType(h);
  if t = 2 then PLongWord(st + 24)^ := $2190          { FILE_TYPE_CHAR: S_IFCHR | 0620 }
  else if t = 3 then PLongWord(st + 24)^ := $1180     { FILE_TYPE_PIPE: S_IFIFO | 0600 }
  else PLongWord(st + 24)^ := $8180;                  { S_IFREG | 0600 }
  PInt64(st + 56)^ := 4096;                           { st_blksize }
  Result := 0;
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
  PInt64(ptrs)^ := 0; ptrs := ptrs + 8;              { envp's NULL }
  PInt64(ptrs)^ := 0; ptrs := ptrs + 8;              { AT_NULL }
  PInt64(ptrs)^ := 0; ptrs := ptrs + 8;
  PInt64(blk + 8)^ := argc;
  n := (ptrs - (blk + 8)) shr 3;
  if (n and 1) <> 0 then begin PInt64(ptrs)^ := 0; n := n + 1; end;
  PInt64(blk)^ := n;
  Result := blk;
end;

function PXXWinSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;
begin
  case nr of
    $7F000002: Result := WinArgBlock;             { WIN_PXX_ARGBLOCK: the entry stub }
    0: Result := WinRead(a0, a1, a2);
    1: Result := WinWrite(a0, a1, a2);
    3: Result := WinClose(a0);
    5: Result := WinFstat(a0, a1);
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
