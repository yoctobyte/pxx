---
track: B
prio: 40
type: feature
blocked-by: []
summary: "FPC's `Signal(sig, handler)` / `fpSignal` surface, where the handler takes the signal NUMBER, on top of pxx's parameterless SetSignalHandler intrinsic. The compiler half landed (__pxxSigNum, so one hook can tell which signal fired); what is missing is the RTL unit, which is lib/rtl and therefore Track B's."
status: done
owner: frankB
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

## Resolved 2026-08-28 (Track B, frankB)

`lib/rtl/signals.pas` — table plus one trampoline, as the ticket specified, with
`test/lib_signals_fpc.pas` in `lib-test`. All three "decide, do not guess" items
were settled by measurement rather than by picking the safe-looking option, and
two of the three came out better than the ticket budgeted for.

### `SIG_IGN` — honest, and no Track A ticket needed

The ticket's contingency was: if the runtime cannot express *ignore*, make
`Signal(x, SIG_IGN)` an explicit error, and if fixing that needs a compiler
change, file it as Track A. It does not need one. **`PalIgnoreSignal` is already
exported from `lib/rtl/platform.pas`** and installs `sa_handler=SIG_IGN` through
`rt_sigaction` (`platform_backend.pas:392`). So ignore is a real ignore, and
`SIG_DFL` separately maps to `SetSignalHandler(sig, nil)`.

Same shape as the rest of tonight: the capability existed and the ticket's
premise was a claim about a search, not about the runtime.

### `cdecl` on a procedure type — accepted

Measured before relying on it, per the ticket. `procedure(sig: Longint); cdecl;`
compiles, and a call through a variable of that type reaches the handler with
the right argument. It is meaningless here — pxx is libc-free and calls the
trampoline with its own ABI — but corpus source spells it, so the declaration
matches what real code writes.

Typed-constant casts (`SIG_DFL = SignalHandler(0)`) and procedure-variable
comparison both work too, so FPC's exact spelling of the constants carries over.

### x86-64 only — refuses loudly, does not compile empty

`{$ifndef CPUX86_64}` + `{$error ...}`. The define is `CPUX86_64` (measured; not
`CPU_X86_64`). The important half is what the `{$else}` does NOT do: compiling to
an empty unit would satisfy a `uses` clause and provide no dispositions at all,
which is the "paper over" the ticket forbids. Negative-controlled by building the
unit with the guard inverted — the intended message appears and the compile
fails.

**Found while doing this:** `{$FATAL}` is silently ignored — the frontend
dispatches `warning`/`message`/`error` and no-ops everything else, so a guard
that means "stop, unsupported configuration" compiles clean and yields a binary
that should not exist. Filed as
[[bug-p-fatal-directive-is-silently-ignored]] (Track P). `{$ERROR}` works and is
what this unit uses.

### The two negative controls

Both target the ticket's own stated risk, that a single-signal test passes
against a hard-wired trampoline:

- **Trampoline pinned to a constant number** → `per-signal-number=FAIL usr1=3
  usr2=0 other=0`. Exactly the predicted bug, caught by the one row designed for
  it.
- **`SIG_IGN` quietly mapped to `SIG_DFL`** → the process is killed by SIGPIPE,
  exit **141**, with the `ignore=` line never printed. That is the argument for
  the honest implementation stated as an observation rather than a worry: a wrong
  disposition is invisible until the signal arrives, and then it is fatal.

The sentinel is unreachable on failure (`SIGNALS FAIL`, halt 1) and the Makefile
compares the whole output, so the FAIL lines survive as the diagnostic.

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.
