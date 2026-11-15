{ sysvipc.inc -- System V IPC (shm*, sem*, msg*) for the BSD translators,
  the Linux way.

  All four BSDs have the three families in the kernel, with Linux's flag bits
  (IPC_CREAT 01000, IPC_EXCL, IPC_NOWAIT, SHM_RDONLY, SHM_RND, SEM_UNDO,
  MSG_NOERROR), its IPC_RMID/IPC_SET/IPC_STAT, and its struct sembuf. What
  differs is translated here: the *_ds structs (each BSD has its own layout,
  measured on the VMs with offsetof), semctl's other command numbers, and the
  union semun, which Linux's semctl takes as a value and the BSD kernels
  through a pointer (the host's IpcHost turns one into the other).

  The host unit defines, before the include:

    IPC_UID          offset of ipc_perm.uid: 8 (cuid, cgid, uid, gid) or 0
                     (NetBSD: uid, gid, cuid, cgid); gid follows it, and the
                     other pair is the creator's
    IPC_MODE16       ipc_perm.mode is 16 bits with seq at 18 (FreeBSD,
                     DragonFly), not 32 bits with seq at 20. key is a long at
                     24 everywhere.
    IPC_SHM: array[0..9] of Integer    shmid_ds: segsz offset, its size,
                     lpid, cpid, nattch offset, its size, atime, dtime,
                     ctime, sizeof
    IPC_MSG: array[0..8] of Integer    msqid_ds: cbytes, qnum, qbytes,
                     lspid, lrpid, stime, rtime, ctime, sizeof
    IPC_SEM: array[0..3] of Integer    semid_ds: nsems (16 bits), otime,
                     ctime, sizeof
    IPC_SHMLOCK      its SHM_LOCK (SHM_UNLOCK is the next number)
    function IpcHost(op, a0, a1, a2, a3, a4: Int64): Int64;
                     the host's call for IPC_OP_* below, answering >= 0 or a
                     -Linux errno. For IPC_OP_SEMCTL a3 is the union semun's
                     value, as Linux passes it. IPC_OP_SEMTIMEDOP answers
                     -LX_ENOSYS where the system has no such call, and the
                     timed wait is then polled here.
    procedure IpcNap;  sleep about a millisecond

  What it gives: IpcLinux(nr, ...), the twelve calls under their x86-64
  Linux numbers (arm64's front maps its own onto these). The structs handed
  back are the Linux kernel's ipc64 ones, which crtl's <sys/*.h> declare.
  Linux-only commands (IPC_INFO, SHM_STAT, SHM_INFO, MSG_STAT, MSG_INFO,
  SEM_STAT, SEM_INFO) and flags (MSG_EXCEPT, MSG_COPY) answer EINVAL. }

const
  IPC_OP_SHMGET = 1; IPC_OP_SHMAT = 2; IPC_OP_SHMDT = 3; IPC_OP_SHMCTL = 4;
  IPC_OP_SEMGET = 5; IPC_OP_SEMOP = 6; IPC_OP_SEMCTL = 7; IPC_OP_SEMTIMEDOP = 8;
  IPC_OP_MSGGET = 9; IPC_OP_MSGSND = 10; IPC_OP_MSGRCV = 11; IPC_OP_MSGCTL = 12;

  IPC_LX_EINVAL = 22; IPC_LX_EAGAIN = 11; IPC_LX_ENOSYS = 38;
  IPC_GETFLAGS = $7FF;               { mode bits, IPC_CREAT, IPC_EXCL }

  { Linux's struct semid64_ds: x86-64 keeps a spare long after each time,
    arm64 (asm-generic) does not. }
{$ifdef CPU_AARCH64}
  IPC_LXSEM_OTIME = 48; IPC_LXSEM_CTIME = 56; IPC_LXSEM_NSEMS = 64; IPC_LXSEM_SIZE = 88;
{$else}
  IPC_LXSEM_OTIME = 48; IPC_LXSEM_CTIME = 64; IPC_LXSEM_NSEMS = 80; IPC_LXSEM_SIZE = 104;
{$endif}

function IpcRd(p: Int64; size: Integer): Int64;
begin
  if size = 2 then Result := PWord(p)^
  else if size = 4 then Result := Int64(PInteger(p)^) and $FFFFFFFF
  else Result := PInt64(p)^;
end;

procedure IpcWr(p: Int64; size: Integer; v: Int64);
begin
  if size = 2 then PWord(p)^ := Word(v)
  else if size = 4 then PInteger(p)^ := Integer(v)
  else PInt64(p)^ := v;
end;

procedure IpcZero(p: Int64; n: Integer);
var i: Integer;
begin
  for i := 0 to n - 1 do PByte(p + i)^ := 0;
end;

{ Linux ipc64_perm: key int @0, uid gid cuid cgid @4..16, mode @20, seq
  (16 bits) @24, two spare longs @32. }
procedure IpcPermToLx(b, l: Int64);
var c: Int64;
begin
  if IPC_UID = 0 then c := 8 else c := 0;
  PInteger(l)^ := Integer(PInt64(b + 24)^);
  PInteger(l + 4)^ := PInteger(b + IPC_UID)^;
  PInteger(l + 8)^ := PInteger(b + IPC_UID + 4)^;
  PInteger(l + 12)^ := PInteger(b + c)^;
  PInteger(l + 16)^ := PInteger(b + c + 4)^;
  if IPC_MODE16 then
  begin
    PInteger(l + 20)^ := PWord(b + 16)^ and $1FF;
    PWord(l + 24)^ := PWord(b + 18)^;
  end
  else
  begin
    PInteger(l + 20)^ := PInteger(b + 16)^ and $1FF;
    PWord(l + 24)^ := PWord(b + 20)^;
  end;
end;

{ IPC_SET changes the owner and the permission bits, on Linux and here. }
procedure IpcPermFromLx(l, b: Int64);
begin
  PInteger(b + IPC_UID)^ := PInteger(l + 4)^;
  PInteger(b + IPC_UID + 4)^ := PInteger(l + 8)^;
  if IPC_MODE16 then
    PWord(b + 16)^ := Word((PWord(b + 16)^ and not $1FF) or (PInteger(l + 20)^ and $1FF))
  else
    PInteger(b + 16)^ := (PInteger(b + 16)^ and not $1FF) or (PInteger(l + 20)^ and $1FF);
end;

{ Linux shmid64_ds (112): perm, segsz @48, atime @56, dtime @64, ctime @72,
  cpid @80, lpid @84 (ints), nattch @88. }
procedure IpcShmToLx(b, l: Int64);
begin
  IpcZero(l, 112);
  IpcPermToLx(b, l);
  PInt64(l + 48)^ := IpcRd(b + IPC_SHM[0], IPC_SHM[1]);
  PInt64(l + 56)^ := PInt64(b + IPC_SHM[6])^;
  PInt64(l + 64)^ := PInt64(b + IPC_SHM[7])^;
  PInt64(l + 72)^ := PInt64(b + IPC_SHM[8])^;
  PInteger(l + 80)^ := PInteger(b + IPC_SHM[3])^;
  PInteger(l + 84)^ := PInteger(b + IPC_SHM[2])^;
  PInt64(l + 88)^ := IpcRd(b + IPC_SHM[4], IPC_SHM[5]);
end;

{ Linux msqid64_ds (120): perm, stime @48, rtime @56, ctime @64, cbytes @72,
  qnum @80, qbytes @88, lspid @96, lrpid @100. }
procedure IpcMsgToLx(b, l: Int64);
begin
  IpcZero(l, 120);
  IpcPermToLx(b, l);
  PInt64(l + 48)^ := PInt64(b + IPC_MSG[5])^;
  PInt64(l + 56)^ := PInt64(b + IPC_MSG[6])^;
  PInt64(l + 64)^ := PInt64(b + IPC_MSG[7])^;
  PInt64(l + 72)^ := PInt64(b + IPC_MSG[0])^;
  PInt64(l + 80)^ := PInt64(b + IPC_MSG[1])^;
  PInt64(l + 88)^ := PInt64(b + IPC_MSG[2])^;
  PInteger(l + 96)^ := PInteger(b + IPC_MSG[3])^;
  PInteger(l + 100)^ := PInteger(b + IPC_MSG[4])^;
end;

procedure IpcSemToLx(b, l: Int64);
begin
  IpcZero(l, IPC_LXSEM_SIZE);
  IpcPermToLx(b, l);
  PInt64(l + IPC_LXSEM_OTIME)^ := PInt64(b + IPC_SEM[1])^;
  PInt64(l + IPC_LXSEM_CTIME)^ := PInt64(b + IPC_SEM[2])^;
  PInt64(l + IPC_LXSEM_NSEMS)^ := PWord(b + IPC_SEM[0])^;
end;

{ shmctl and msgctl: IPC_STAT through a host-shaped buffer, and IPC_SET as a
  STAT, the changed fields, then the SET -- the host's struct has fields
  Linux's has not, and those must go back as they were. }
function IpcCtl(op, id, cmd, buf: Int64): Int64;
var b: array[0..23] of Int64;       { 192 bytes: the largest host struct is 160 }
    r: Int64;
begin
  cmd := cmd and not $100;          { IPC_64: the direct Linux calls imply it }
  case Integer(cmd) of
    0: Result := IpcHost(op, id, 0, 0, 0, 0);                   { IPC_RMID }
    1, 2:
      begin
        if buf = 0 then begin Result := -14; Exit; end;         { EFAULT }
        IpcZero(Int64(@b[0]), SizeOf(b));
        r := IpcHost(op, id, 2, Int64(@b[0]), 0, 0);
        if (r >= 0) and (cmd = 2) then
        begin
          if op = IPC_OP_SHMCTL then IpcShmToLx(Int64(@b[0]), buf)
          else IpcMsgToLx(Int64(@b[0]), buf);
        end
        else if r >= 0 then
        begin
          IpcPermFromLx(buf, Int64(@b[0]));
          if op = IPC_OP_MSGCTL then PInt64(Int64(@b[0]) + IPC_MSG[2])^ := PInt64(buf + 88)^;
          r := IpcHost(op, id, 1, Int64(@b[0]), 0, 0);
        end;
        Result := r;
      end;
    11, 12:                                                     { SHM_LOCK, SHM_UNLOCK }
      if (op = IPC_OP_SHMCTL) and (IPC_SHMLOCK <> 0) then
        Result := IpcHost(op, id, IPC_SHMLOCK + cmd - 11, 0, 0, 0)
      else Result := -IPC_LX_EINVAL;
  else Result := -IPC_LX_EINVAL;
  end;
end;

{ semctl: Linux's GETPID 11 .. SETALL 17 are the BSDs' 4 5 6 3 7 8 9. }
function IpcSemctl(id, num, cmd, arg: Int64): Int64;
var b: array[0..23] of Int64;
    r: Int64;
begin
  cmd := cmd and not $100;
  case Integer(cmd) of
    0: Result := IpcHost(IPC_OP_SEMCTL, id, 0, 0, 0, 0);
    1, 2:
      begin
        if arg = 0 then begin Result := -14; Exit; end;
        IpcZero(Int64(@b[0]), SizeOf(b));
        r := IpcHost(IPC_OP_SEMCTL, id, 0, 2, Int64(@b[0]), 0);
        if (r >= 0) and (cmd = 2) then IpcSemToLx(Int64(@b[0]), arg)
        else if r >= 0 then
        begin
          IpcPermFromLx(arg, Int64(@b[0]));
          r := IpcHost(IPC_OP_SEMCTL, id, 0, 1, Int64(@b[0]), 0);
        end;
        Result := r;
      end;
    11: Result := IpcHost(IPC_OP_SEMCTL, id, num, 4, 0, 0);     { GETPID }
    12: Result := IpcHost(IPC_OP_SEMCTL, id, num, 5, 0, 0);     { GETVAL }
    13: Result := IpcHost(IPC_OP_SEMCTL, id, 0, 6, arg, 0);     { GETALL }
    14: Result := IpcHost(IPC_OP_SEMCTL, id, num, 3, 0, 0);     { GETNCNT }
    15: Result := IpcHost(IPC_OP_SEMCTL, id, num, 7, 0, 0);     { GETZCNT }
    16: Result := IpcHost(IPC_OP_SEMCTL, id, num, 8, Int64(Integer(arg)), 0);   { SETVAL: an int }
    17: Result := IpcHost(IPC_OP_SEMCTL, id, 0, 9, arg, 0);     { SETALL }
  else Result := -IPC_LX_EINVAL;
  end;
end;

{ semtimedop where the system has none: semop with IPC_NOWAIT on every
  operation, once a millisecond, until it goes through or the time is up
  (EAGAIN, as Linux says when the timeout passes). An operation the caller
  marked IPC_NOWAIT already fails at once, as it would have. }
function IpcSemTimed(id, sops, nsops, ts: Int64): Int64;
var ops: array[0..191] of Word;       { 64 sembufs of 3 words }
    i, waited, limit: Int64;
    nowait: Boolean;
begin
  Result := IpcHost(IPC_OP_SEMTIMEDOP, id, sops, nsops, ts, 0);
  if Result <> -IPC_LX_ENOSYS then Exit;
  if ts = 0 then begin Result := IpcHost(IPC_OP_SEMOP, id, sops, nsops, 0, 0); Exit; end;
  if (nsops < 0) or (nsops > 64) then begin Result := -7; Exit; end;    { E2BIG }
  if (PInt64(ts)^ < 0) or (PInt64(ts + 8)^ < 0) or (PInt64(ts + 8)^ >= 1000000000) then
  begin
    Result := -IPC_LX_EINVAL; Exit;
  end;
  nowait := False;
  for i := 0 to nsops * 3 - 1 do ops[i] := PWord(sops + 2 * i)^;
  for i := 0 to nsops - 1 do
  begin
    if (ops[3 * i + 2] and $800) <> 0 then nowait := True;
    ops[3 * i + 2] := ops[3 * i + 2] or $800;                   { IPC_NOWAIT }
  end;
  limit := PInt64(ts)^ * 1000;
  waited := PInt64(ts + 8)^;
  while waited > 0 do begin Inc(limit); waited := waited - 1000000; end;   { whole ms, rounded up }
  waited := 0;
  repeat
    Result := IpcHost(IPC_OP_SEMOP, id, Int64(@ops[0]), nsops, 0, 0);
    if (Result <> -IPC_LX_EAGAIN) or nowait or (waited >= limit) then Exit;
    IpcNap;
    Inc(waited);
  until False;
end;

function IpcLinux(nr, a0, a1, a2, a3, a4: Int64): Int64;
begin
  case Integer(nr) of
    29: Result := IpcHost(IPC_OP_SHMGET, a0, a1, a2 and IPC_GETFLAGS, 0, 0);
    30: Result := IpcHost(IPC_OP_SHMAT, a0, a1, a2 and $3000, 0, 0);    { SHM_RDONLY, SHM_RND }
    67: Result := IpcHost(IPC_OP_SHMDT, a0, 0, 0, 0, 0);
    31: Result := IpcCtl(IPC_OP_SHMCTL, a0, a1, a2);
    64: Result := IpcHost(IPC_OP_SEMGET, a0, a1, a2 and IPC_GETFLAGS, 0, 0);
    65: Result := IpcHost(IPC_OP_SEMOP, a0, a1, a2, 0, 0);
    220: Result := IpcSemTimed(a0, a1, a2, a3);
    66: Result := IpcSemctl(a0, a1, a2, a3);
    68: Result := IpcHost(IPC_OP_MSGGET, a0, a1 and IPC_GETFLAGS, 0, 0, 0);
    69: Result := IpcHost(IPC_OP_MSGSND, a0, a1, a2, a3 and $800, 0);     { IPC_NOWAIT }
    70: if (a4 and $6000) <> 0 then Result := -IPC_LX_EINVAL                { MSG_EXCEPT, MSG_COPY }
        else Result := IpcHost(IPC_OP_MSGRCV, a0, a1, a2, a3, a4 and $1800);   { IPC_NOWAIT, MSG_NOERROR }
    71: Result := IpcCtl(IPC_OP_MSGCTL, a0, a1, a2);
  else Result := -IPC_LX_ENOSYS;
  end;
end;
