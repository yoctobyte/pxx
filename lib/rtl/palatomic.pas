{ SPDX-License-Identifier: Zlib }
unit palatomic;
{ FPC's InterLocked* atomic counter family, over the __pxxatomic_* intrinsics.

  WHY ITS OWN UNIT rather than palsync, where the intrinsics are already used:
  an atomic counter needs no thread support to COMPILE — plenty of code uses
  InterLockedIncrement for a refcount in a program that never spawns anything —
  so it must not drag the __pxxclone / --threadsafe gate in. When this unit was
  written, palsync `uses palthread` and so did drag it in; that has since been
  fixed by splitting the futex wrappers into `palfutex`
  (bug-b-futex-helpers-are-trapped-behind-pxxclone), so palsync is now
  gate-free too. Staying separate is still the right shape — a refcount bump
  has no business pulling in mutexes, events and condvars — but it is now a
  layering choice rather than a workaround. This unit has no dependencies.

  FPC declares these in the `system` unit, so real code calls them with no
  `uses` line. Here they need `uses palatomic` until they are reachable the way
  FPC's are (bug-a-interlocked-family-needs-a-uses-clause-unlike-fpc).

  TARGETS: x86-64, i386, arm32 and aarch64 all work (the 32-bit ones get the
  32-bit half only — see the CPU64 guard below). riscv32 and xtensa cannot use
  this unit at ALL: their backends have no atomic node yet ("target riscv32:
  unsupported node in IR codegen: atomic"), so even `uses palatomic` fails to
  build there — bug-a-riscv32-and-xtensa-have-no-atomic-codegen.

  RETURN VALUES ARE NOT UNIFORM, and this is FPC's convention, not an accident:
  Increment/Decrement return the value AFTER the operation — that is what makes
  the standard `if InterLockedDecrement(FRefCount) = 0 then Free` correct —
  while Exchange/ExchangeAdd/CompareExchange return the value BEFORE it. The
  underlying intrinsics all return the old value, so only the first two adjust. }

interface

function InterLockedIncrement(var Target: LongInt): LongInt;
function InterLockedDecrement(var Target: LongInt): LongInt;
function InterLockedExchange(var Target: LongInt; Source: LongInt): LongInt;
function InterLockedExchangeAdd(var Target: LongInt; Source: LongInt): LongInt;
function InterLockedCompareExchange(var Target: LongInt;
                                    NewValue, Comperand: LongInt): LongInt;

{ 64-bit peers, on the *64 intrinsics. DECLARED ONLY ON 64-BIT TARGETS: a
  32-bit target has no single-instruction 64-bit read-modify-write, and the
  intrinsic refuses at compile time ("target i386: __pxxatomic_*64 not
  supported"). Without this guard the DECLARATIONS alone break `uses palatomic`
  for every 32-bit target — the unit is compiled whole, so even a program that
  only wants InterLockedIncrement fails to build. A silently non-atomic 32-bit
  fallback would be worse than either. }
{$IFDEF CPU64}
function InterLockedIncrement64(var Target: Int64): Int64;
function InterLockedDecrement64(var Target: Int64): Int64;
function InterLockedExchange64(var Target: Int64; Source: Int64): Int64;
function InterLockedExchangeAdd64(var Target: Int64; Source: Int64): Int64;
function InterLockedCompareExchange64(var Target: Int64;
                                      NewValue, Comperand: Int64): Int64;
{$ENDIF}

implementation

function InterLockedIncrement(var Target: LongInt): LongInt;
begin
  Result := LongInt(__pxxatomic_add(@Target, 1)) + 1;
end;

function InterLockedDecrement(var Target: LongInt): LongInt;
begin
  Result := LongInt(__pxxatomic_add(@Target, -1)) - 1;
end;

function InterLockedExchange(var Target: LongInt; Source: LongInt): LongInt;
begin
  Result := LongInt(__pxxatomic_xchg(@Target, Source));
end;

function InterLockedExchangeAdd(var Target: LongInt; Source: LongInt): LongInt;
begin
  Result := LongInt(__pxxatomic_add(@Target, Source));
end;

function InterLockedCompareExchange(var Target: LongInt;
                                    NewValue, Comperand: LongInt): LongInt;
begin
  { note the ARGUMENT ORDER: FPC takes (new, expected), the intrinsic takes
    (expected, new). Swapping them is the whole point of this wrapper. }
  Result := LongInt(__pxxatomic_cas(@Target, Comperand, NewValue));
end;

{$IFDEF CPU64}
function InterLockedIncrement64(var Target: Int64): Int64;
begin
  Result := __pxxatomic_add64(@Target, 1) + 1;
end;

function InterLockedDecrement64(var Target: Int64): Int64;
begin
  Result := __pxxatomic_add64(@Target, -1) - 1;
end;

function InterLockedExchange64(var Target: Int64; Source: Int64): Int64;
begin
  Result := __pxxatomic_xchg64(@Target, Source);
end;

function InterLockedExchangeAdd64(var Target: Int64; Source: Int64): Int64;
begin
  Result := __pxxatomic_add64(@Target, Source);
end;

function InterLockedCompareExchange64(var Target: Int64;
                                      NewValue, Comperand: Int64): Int64;
begin
  Result := __pxxatomic_cas64(@Target, Comperand, NewValue);
end;
{$ENDIF}

end.
