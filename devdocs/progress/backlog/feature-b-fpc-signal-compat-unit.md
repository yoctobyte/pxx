---
track: B
prio: 40
type: feature
blocked-by: []
summary: "FPC's `Signal(sig, handler)` / `fpSignal` surface, where the handler takes the signal NUMBER, on top of pxx's parameterless SetSignalHandler intrinsic. The compiler half landed (__pxxSigNum, so one hook can tell which signal fired); what is missing is the RTL unit, which is lib/rtl and therefore Track B's."
status: backlog
owner: unassigned
---

# B an FPC-compatible `Signal()` unit over SetSignalHandler

- **Track B** (`lib/rtl` — a new unit, plus `baseunix.pas` for the `fp*`
  spelling). Filed rather than written by Track A because `lib/rtl` is B's
  file-lane; the compiler half is done and pushed.
- Item 4 of [[feature-signal-siginfo-ucontext]]. That ticket keeps items 2 and 5.

## What already exists (nothing to build in the compiler)

- `SetSignalHandler(sig, @proc)` — installs a **parameterless** Pascal hook,
  libc-free, on every hosted target. That ABI is deliberately fixed: every
  existing user depends on it.
- `__pxxSigNum` — **landed 2026-08-20**. The signal number currently being
  dispatched, parked by the dispatch stub and read from inside the hook. It is
  what makes ONE procedure able to serve several signals, which is exactly the
  gap between pxx's ABI and FPC's. `test/test_signal_num.pas`.
- `__pxxSigCode` / `__pxxSigAddr` / `__pxxSigContext` / `__pxxSigPCPtr` for the
  fault details, if a richer `sigaction`-shaped surface is wanted later.

## The work

A unit exporting FPC's shape:

```pascal
type
  SignalHandler = procedure(sig: Longint);
  TSignalHandler = SignalHandler;
const
  SIG_DFL = 0; SIG_IGN = 1; SIG_ERR = -1;
function Signal(signum: Longint; handler: SignalHandler): SignalHandler;
```

The implementation is a table plus one trampoline, and needs no new compiler
support:

```pascal
var Handlers: array[1..64] of SignalHandler;
procedure Trampoline;
begin
  if Assigned(Handlers[__pxxSigNum]) then Handlers[__pxxSigNum](__pxxSigNum);
end;
```

`Signal` stores into `Handlers[signum]`, calls `SetSignalHandler(signum,
@Trampoline)` once per signal, and returns the previous entry — FPC's contract.

Also worth exporting, since corpus code spells them either way:
`fpSignal` (the BaseUnix name) and the `SIGxxx` number constants, which the
existing signal tests currently spell as bare integers.

## Decide while writing it, do not guess

- **`SIG_IGN` / `SIG_DFL`.** pxx's `SetSignalHandler(sig, nil)` reverts to the
  default disposition on the next delivery. FPC's `SIG_IGN` is *ignore*, which
  is a different thing (`SIG_IGN` must not terminate). If the runtime cannot
  express ignore, the honest move is to make `Signal(x, SIG_IGN)` an explicit
  error rather than silently mean SIG_DFL — a wrong disposition is invisible
  until the signal arrives. If that needs a compiler change, file it as Track A.
- **`cdecl` on the handler type.** FPC declares it `cdecl` because libc calls
  it. pxx is libc-free and calls the trampoline with its own ABI, so the
  modifier is meaningless here — but corpus SOURCE will spell it, so check that
  pxx accepts and ignores `cdecl` on a procedure type before assuming it does.
- **x86-64 only, today.** `__pxxSigNum` REFUSES on the other four hosted targets
  (their dispatch stubs do not park the number yet), so this unit will not
  compile there. That is deliberate — answering 0 would send every signal to
  handler 0. Either gate the unit on the target, or wait for the follow-up
  slice; do not paper over it.

## Gate

Track B's: build with `$(PXX_STABLE)`, `make lib-test` / `demos`. A test that
registers one handler for two different signals and asserts each got its own
number is the one that bites — a single-signal test passes even with the
trampoline hard-wired.
