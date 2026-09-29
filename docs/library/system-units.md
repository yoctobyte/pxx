---
title: System units
order: 57
---

# System units: signals, locks, shared libraries, bit arrays, atexit

Five small units that sit close to the operating system. Four are for Pascal
and follow Free Pascal's names, so code written for FPC compiles unchanged;
`atexit` is for Nil Python and follows CPython's.

| Unit | For | What it does |
| --- | --- | --- |
| [`signals`](#signals-reacting-to-unix-signals) | Pascal | Install a handler for a Unix signal |
| [`syncobjs`](#syncobjs-a-lock-for-threads) | Pascal | `TCriticalSection`, a lock shared by threads |
| [`dynlibs`](#dynlibs-loading-a-shared-library-at-run-time) | Pascal | Load a `.so` file at run time and call into it |
| [`bitset`](#bitset-a-growable-bit-array) | Pascal | A bit array of any length |
| [`atexit`](#atexit-running-code-when-the-program-ends) | Nil Python | Run functions when the program ends |

Each example below was built with pin v451 (compiler sha256 `d9b7226769cc`)
through `./pxx` on Linux x86-64 on 2026-09-29, and its output compared with
FPC 3.2.2 or CPython 3.14.4 as stated.

## signals: reacting to Unix signals

`fpSignal(sig, handler)` (also spelled `Signal`) installs `handler` for one
signal and returns the previous handler. The handler is a `cdecl` procedure
that receives the signal's number, so one handler can serve several signals.
The unit has the usual constants (`SIGINT`, `SIGTERM`, `SIGHUP`, `SIGUSR1`,
`SIGUSR2` and so on) and `SIG_DFL`, `SIG_IGN` and `SIG_ERR`. `SIGKILL` and
`SIGSTOP` cannot be caught, and `fpSignal` returns `SIG_ERR` for them.

In FPC the same routine is in `baseunix`. This program waits until another
process sends it signals: `SIGUSR1` counts a reload, `SIGTERM` makes it stop.

```pascal
program sig_demo;

uses {$ifdef PXX} signals, {$else} baseunix, {$endif} sysutils;

var
  reloads: Integer = 0;
  stopping: Boolean = False;

procedure OnSignal(sig: Longint); cdecl;
begin
  if sig = SIGUSR1 then Inc(reloads)
  else if sig = SIGTERM then stopping := True;
end;

begin
  fpSignal(SIGUSR1, @OnSignal);
  fpSignal(SIGTERM, @OnSignal);
  writeln('waiting');
  Flush(Output);
  while not stopping do
    Sleep(50);
  writeln('reloads: ', reloads);
  writeln('stopped cleanly');
end.
```

```sh
./pxx sig_demo.pas sig_demo
./sig_demo & pid=$!
sleep 1; kill -USR1 $pid; sleep 0.3; kill -USR1 $pid; sleep 0.3; kill -TERM $pid
wait $pid; echo "exit status $?"
```

```text
waiting
reloads: 2
stopped cleanly
exit status 0
```

FPC 3.2.2 prints the same four lines. `PXX` is defined by the PXX compiler,
so one source serves both.

Signals need an operating system's signal runtime. Built for windowed Xtensa
(the ESP32-S3's calling convention), the program above does not compile
("`__pxxSigNum` needs SA_SIGINFO, which this target's signal runtime does
not install"), and the unit's source says the same of every ESP build.

## syncobjs: a lock for threads

`TCriticalSection` has `Enter` and `Leave` (also spelled `Acquire` and
`Release`) and `TryEnter`, which returns `True` if it took the lock. A thread
waiting for the lock sleeps rather than spinning. As in FPC on Linux, the
lock is not recursive: entering it a second time from the same thread hangs,
and `TryEnter` on a lock that is held returns `False`.

Four threads add 2,000 each to one counter:

```pascal
program lock_demo;
{$mode objfpc}
uses {$ifdef FPC} cthreads, {$endif} classes, syncobjs;

type
  TWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  Lock: TCriticalSection;
  Total: Integer = 0;

procedure TWorker.Execute;
var i: Integer;
begin
  for i := 1 to 2000 do
  begin
    Lock.Enter;
    Total := Total + 1;
    Lock.Leave;
  end;
end;

var
  w: array[0..3] of TWorker;
  i: Integer;
begin
  Lock := TCriticalSection.Create;
  for i := 0 to 3 do w[i] := TWorker.Create(False);
  for i := 0 to 3 do begin w[i].WaitFor; w[i].Free; end;
  writeln('total: ', Total);
  writeln('TryEnter on a free lock: ', Lock.TryEnter);
  Lock.Leave;
  Lock.Free;
end.
```

```sh
./pxx --threadsafe lock_demo.pas lock_demo && ./lock_demo
```

```text
total: 8000
TryEnter on a free lock: TRUE
```

FPC 3.2.2 prints the same, and three runs gave 8000 each time. A program
that starts threads needs `--threadsafe`. Without it, v451 stops at the
`TThread` class with "base type not found: TThread", which does not name
the flag. `syncobjs` alone, without threads, needs no flag.

## dynlibs: loading a shared library at run time

`LoadLibrary(name)` returns a `TLibHandle`, or `NilHandle` if the library
could not be loaded. `GetProcedureAddress(lib, name)` returns a pointer to a
function, or `nil`, and `UnloadLibrary(lib)` closes it. `HModule`, `GetProcAddress` and `FreeLibrary` are
the Delphi spellings of the same things.

A PXX program does not link the C library, and by default it has no dynamic
loader either: `LoadLibrary` then always returns `NilHandle`, so code that
treats a library as optional keeps working. Build with `-dPXX_DYNLIB_LIBC`
to get the real loader. The program then links `libc.so.6`.

```pascal
program dl_demo;
uses dynlibs;

type
  TCos = function(x: Double): Double; cdecl;

var
  lib: TLibHandle;
  c: TCos;
begin
  lib := LoadLibrary('libm.so.6');
  if lib = NilHandle then
  begin
    writeln('libm not loaded');
    Halt(0);
  end;
  c := TCos(GetProcedureAddress(lib, 'cos'));
  if c = nil then writeln('cos not found')
  else writeln('cos(0) = ', c(0.0):0:3);
  writeln('missing symbol: ', GetProcedureAddress(lib, 'no_such_function') = nil);
  writeln('unloaded: ', UnloadLibrary(lib));
end.
```

```sh
./pxx -dPXX_DYNLIB_LIBC dl_demo.pas dl_demo && ./dl_demo
```

```text
cos(0) = 1.000
missing symbol: TRUE
unloaded: TRUE
```

FPC 3.2.2 prints the same. Built without `-dPXX_DYNLIB_LIBC`, the program is
a static executable and prints `libm not loaded`. The ESP32 has no loader;
the unit's source says it always behaves like the default build there.

`GetLoadErrorStr` does not say why a load failed. After
`LoadLibrary('libdoes_not_exist.so')` it returns the fixed text
`dynlibs: see dlerror (libc loader)`, where FPC returns the loader's message
(`libdoes_not_exist.so: cannot open shared object file: No such file or
directory`).

## bitset: a growable bit array

A `TBitArray` holds any number of bits, all zero after `BitArrayInit(ba, n)`.
Bits are numbered from 0. `BitArraySetBit`, `BitArrayClearBit` and
`BitArrayToggle` change one bit, `BitArrayTestBit` reads one,
`BitArrayCount` counts the set bits, and `BitArrayNextSet(ba, from)` finds
the first set bit at or after `from` (-1 if none). This unit is PXX's own;
FPC's `TBits` class in `classes` is a different interface.

A sieve that marks the numbers below 100 that are not prime:

```pascal
program bits_demo;
uses bitset;

var
  composite: TBitArray;
  i, j, p, shown: Integer;
begin
  BitArrayInit(composite, 100);
  BitArraySetBit(composite, 0);
  BitArraySetBit(composite, 1);
  for i := 2 to 9 do
    if not BitArrayTestBit(composite, i) then
    begin
      j := i * i;
      while j < 100 do begin BitArraySetBit(composite, j); j := j + i; end;
    end;
  writeln('primes below 100: ', 100 - BitArrayCount(composite));
  BitArrayToggle(composite, 97);           { 97 is prime: now marked }
  writeln('97 marked: ', BitArrayTestBit(composite, 97));
  BitArrayClearBit(composite, 97);
  write('first ten:');
  shown := 0;
  p := 0;
  while shown < 10 do
  begin
    if not BitArrayTestBit(composite, p) then begin write(' ', p); Inc(shown); end;
    Inc(p);
  end;
  writeln;
  writeln('first marked at or after 90: ', BitArrayNextSet(composite, 90));
end.
```

```text
primes below 100: 25
97 marked: TRUE
first ten: 2 3 5 7 11 13 17 19 23 29
first marked at or after 90: 90
```

The same sieve written with a Python set gives the same four lines.

## atexit: running code when the program ends

`atexit.register(fn)` records a function to run when the program ends, and
returns it. The functions run in reverse order of registration, as in
CPython.

```python
import atexit

log = []


def close_log():
    print("closing log with", len(log), "entries")


def say_bye():
    print("bye")


atexit.register(close_log)
atexit.register(say_bye)
log.append("started")
log.append("working")
print("main done")
```

```text
main done
bye
closing log with 2 entries
```

CPython prints the same three lines. Two differences, measured with v451:

- `register` takes only the function. `atexit.register(bye, "x")` stops the
  build ("no overload of register matches these arguments"). Register a
  function that takes no arguments, or a lambda, instead.
- **`atexit.unregister(f)` does nothing when `f` is a def named directly**
  in both calls: `atexit.register(never)` then `atexit.unregister(never)`
  still runs `never` at exit, where CPython does not. It works when both
  calls pass the same variable (`h = never`, then `register(h)` and
  `unregister(h)`), or the value `register` returned. The current compiler
  (`722c38c6faeb`, built at `9bf9b1c173`) behaves the same.
