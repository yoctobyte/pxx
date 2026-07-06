{ Libc-free C `pthread` bridge — the thin façade the crtl `pthread.c` shim binds
  to. Reuses the SAME M1/M2 PAL as native Pascal threads (palthread clone/futex +
  palsync Drepper mutex): one thread layer, two consumers (meta-multithreading).

  Pulled into a C compile only when it uses `<pthread.h>` AND `--threadsafe` is on
  (cparser.inc, next to the pxxcio pull) — the create/join path needs __pxxclone,
  which is a compile error without the thread-safe runtime.

  Names are flat and C-callable; params are pointers so the C-side pthread_t /
  pthread_mutex_t structs bind by address. Only what SQLite (THREADSAFE=1,
  HOMEGROWN recursive mutex) actually references, plus create/join for real
  worker-thread tests. No condition variables / TLS keys — SQLite needs neither. }
unit palpthread;

interface

uses palsync, palthread;

{ pthread_mutex_t == TMutex (a single futex word; zeroed = free). }
procedure __pxx_pmutex_init(m: PMutex);
procedure __pxx_pmutex_lock(m: PMutex);
procedure __pxx_pmutex_unlock(m: PMutex);
function  __pxx_pmutex_trylock(m: PMutex): LongInt;   { 0 = acquired, 16 = EBUSY }

{ pthread_self / pthread_equal: the kernel tid is the identity. }
function  __pxx_pthread_self: Int64;

{ pthread_create / join: h points at a caller-owned TThreadHandle byte block (the
  C shim keeps a tid->handle registry and treats the block as opaque — Pascal
  fills it here, reads it in join, so record-vs-struct layout never matters).
  create returns the child tid (> 0) on success, -1 on failure. entry is the C
  `void*(*)(void*)` start routine — its return value is dropped (PalThread
  entries are void). }
function  __pxx_pthread_create(h: PThreadHandle; entry: TThreadEntry; arg: Pointer): Int64;
procedure __pxx_pthread_join(h: PThreadHandle);

implementation

procedure __pxx_pmutex_init(m: PMutex);   begin MutexInit(m^);   end;
procedure __pxx_pmutex_lock(m: PMutex);   begin MutexLock(m^);   end;
procedure __pxx_pmutex_unlock(m: PMutex); begin MutexUnlock(m^); end;

function __pxx_pmutex_trylock(m: PMutex): LongInt;
begin
  if MutexTryLock(m^) then __pxx_pmutex_trylock := 0
  else __pxx_pmutex_trylock := 16;   { EBUSY }
end;

function __pxx_pthread_self: Int64;
begin
  __pxx_pthread_self := PalThreadSelf;
end;

function __pxx_pthread_create(h: PThreadHandle; entry: TThreadEntry; arg: Pointer): Int64;
begin
  if PalThreadCreate(h^, entry, arg, 0) = 0 then   { 0 => default stack }
    __pxx_pthread_create := h^.Tid
  else
    __pxx_pthread_create := -1;
end;

procedure __pxx_pthread_join(h: PThreadHandle);
begin
  PalThreadJoin(h^);
end;

end.
