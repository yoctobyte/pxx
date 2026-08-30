unit builtinentropy;
{ Hardware entropy (tier 1): the CPUID probe and the RDRAND read.

  WHY IT IS ITS OWN UNIT, and it is not tidiness. These two entry points lived
  in `builtin`, and `pasparser_prog.inc` pulled `builtin` when a program named
  either — behind `(not TargetIsEspClass)`, because `builtin.pas` cannot be
  compiled on a bare ESP boot. So on bare xtensa and bare riscv32 the names
  resolved to nothing and `lib/rtl/random.pas` did not build at all:

    random.pas:321: error: undefined variable (__pxxCpuHasHwRandom)

  That is the wrong failure. The correct answer on those targets is **False** —
  no user-mode hardware RNG instruction exists there, so the library routes
  itself to tier 2 — and the non-x86-64 body below has always said exactly that.
  It simply could not be reached, because the only vehicle carrying it was a
  unit those targets cannot compile.

  A UNIT IS THE GRANULARITY THE COMPILER HAS, so make the unit match the
  feature — builtinwide.pas's rule, and this is its second application. This
  unit deliberately `uses` NOTHING: no heap, no strings, no builtinheap. That is
  the property that lets it be pulled on a bare boot, and it is the whole reason
  the file exists rather than an `{$ifdef}` somewhere.

  DO NOT ADD A DEPENDENCY HERE without re-running the bare-ESP check. The moment
  this unit needs `builtinheap` (or anything that does), it stops being pullable
  on the targets it was created for and the original bug returns wearing a
  different symbol name.
  bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target }

interface

var
  HwRandomProbe: Integer;   { CPUID cache: 0 unknown, 1 has RDRAND, 2 has not }

{ __pxxHwRandom64 REPORTS SUCCESS rather than just handing back a value, and
  that is the whole point of the signature: RDRAND can fail — under load or
  entropy exhaustion it clears CF and leaves the destination ZERO. A caller that
  read the value alone would take a silent zero for entropy, which in the one
  context these instructions exist for is a catastrophic and invisible failure.
  So: False means "no entropy this time, retry a bounded number of times, then
  fall to tier 2".

  __pxxCpuHasHwRandom probes CPUID leaf 1 ECX bit 30 and caches the answer. The
  probe is mandatory, not decorative: the instruction is absent on plenty of
  cores and executing it there is #UD.

  x86-64 only so far. aarch64's MRS RNDR needs FEAT_RNG, which is OPTIONAL and
  needs its own ID_AA64ISAR0_EL1 probe plus system-register support in the a64
  assembler; arm32 and riscv32 have no user-mode instruction at all; ESP's RNG
  register is a Track S item and is only truly random with the RF clock enabled.
  Every non-x86-64 target answers False here, which routes the library to
  tier 2 — the correct answer, not a stub. }
function __pxxCpuHasHwRandom: Boolean;
function __pxxHwRandom64(var v: UInt64): Boolean;

implementation

{$ifdef CPUX86_64}
function __pxxCpuidRdrand: Boolean; assembler;
{$asmMode intel}
asm
  push rbx
  mov eax, 1
  xor ecx, ecx
  cpuid
  shr ecx, 30
  and ecx, 1
  mov eax, ecx
  pop rbx
end;

function __pxxHwRandom64(var v: UInt64): Boolean; assembler;
{$asmMode intel}
asm
  mov rcx, v
  xor edx, edx
  rdrand rax
  setc dl
  mov [rcx], rax
  mov eax, edx
end;
{$endif}

{$ifndef CPUX86_64}
function __pxxCpuidRdrand: Boolean;
begin
  Result := False;
end;

function __pxxHwRandom64(var v: UInt64): Boolean;
begin
  { Not "unimplemented": no user-mode hardware RNG instruction exists on this
    target, so False is the correct answer and routes the caller to tier 2. }
  v := 0;
  Result := False;
end;
{$endif}

function __pxxCpuHasHwRandom: Boolean;
begin
  { Cached: CPUID is serialising and the library asks this on its dispatch
    path. 0 = not probed yet, 1 = yes, 2 = no. Three states, one variable —
    two Booleans that must agree is how one of them ends up stale. }
  if HwRandomProbe = 0 then
  begin
    if __pxxCpuidRdrand then HwRandomProbe := 1 else HwRandomProbe := 2;
  end;
  Result := HwRandomProbe = 1;
end;

end.
