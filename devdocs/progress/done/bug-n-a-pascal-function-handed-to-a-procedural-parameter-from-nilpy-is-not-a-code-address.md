---
track: N
prio: 55
type: bug
owner: frankb-8e
blocked-by: []
summary: "`MkKind(TheMaker)` — a Pascal function name passed from NilPy into a Pascal `function(...)` procedural PARAMETER — stores something that is not a code address, and every later call through it segfaults, INCLUDING a call made from Pascal. Wiring the identical field inside Pascal with `@TheMaker` gives 502 through both languages. The call site is innocent; the value is wrong. Present in the pin."
status: done
---

# A Pascal function handed to a procedural parameter from NilPy is not a code address

```pascal
unit ptrfld2;
interface
type
  TMakeFn = function(laden, room: Integer): Integer;
  TKindRec = class
    build: TMakeFn;
  end;
function TheMaker(laden, room: Integer): Integer;
function MkKindWired: TKindRec;
function MkKind(f: TMakeFn): TKindRec;
function CallItFromPascal(k: TKindRec): Integer;
implementation
function TheMaker(laden, room: Integer): Integer;
begin Result := laden * 100 + room; end;
function MkKindWired: TKindRec;
begin Result := TKindRec.Create; Result.build := @TheMaker; end;
function MkKind(f: TMakeFn): TKindRec;
begin Result := TKindRec.Create; Result.build := f; end;
function CallItFromPascal(k: TKindRec): Integer;
begin Result := k.build(5, 2); end;
end.
```

```python
import 'ptrfld2.pas' as p
k = MkKind(TheMaker)                       # the value crosses NilPy -> Pascal HERE
print(CallItFromPascal(k))                 # SIGSEGV
```

## The measurement that says where it is

| how the field is wired | called from Pascal | called from NilPy |
| --- | --- | --- |
| inside Pascal, `Result.build := @TheMaker` | **502** | **502** |
| from NilPy, `MkKind(TheMaker)` | **SIGSEGV** | **SIGSEGV** |

Both call sites are identical between the rows — only the assignment moved. So
the call lowering is fine and what lands in the slot is not a code address.
The NilPy-side call is not the discriminator either: with the field wired in
Pascal, NilPy calls through it correctly.

Receiver shape is NOT the discriminator here (unlike its neighbour
bug-n-a-keyword-argument-through-a-procedural-field-needs-a-plain-receiver):
`k.build(5, 2)` on a plain-name receiver and `ks[0].build(5, 2)` on a list
element segfault identically.

## Not new

Reproduced under `stable_linux_amd64/default/stable_pinned` (2026-09-06) with the
same SIGSEGV, so it is in the pin and predates the 2026-09-11 keyword work at
this door. Found while building a POSITIVE CONTROL for the new refusal in
PyVariantFieldCallArm — the control was "positional through a typed procedural
field still works", and it did not.

## Likely shape, NOT verified

NilPy takes a function name as a VALUE through its own callable carriers (a
tag-8 pair, a lifted bound-fn object), which is what makes `g = f; g(1)` work and
what `pyvar_callv_kw` reads parameter names out of. A Pascal `TMakeFn` parameter
wants a bare address. Somewhere on that hand-off the carrier is stored whole, or
its payload is read from the wrong word. `PXXDBG=a.ast:` on the call, and the
stored bytes, will say which — do not take this paragraph as the diagnosis.

## Why it matters beyond the repro

This is the ordinary way a Python program configures a Pascal library: hand it a
callback. It fails with no diagnostic at all, at a call that may be far from the
assignment, and it is currently invisible to the suite — the callable-field
fixtures all wire NilPy functions into NilPy-declared fields, which is the case
that works.

## 2026-09-20 (frankS) — what is actually in the slot, measured. NOT fixed; I was moved to another group.

Banked rather than left in a transcript. Reproduced at `74ff679403b8`, x86-64,
exactly the repro above. The probes are three routines added to the unit --
`SlotBits` (`q := @k.build; q^`), `Peek(addr, i)` (word `i` at `addr`) and
`AddrOf(which)` (`@` of each unit routine) -- so every number below is read
through Pascal, not inferred.

```
maker         5558117        <- @TheMaker
wired slot    5558117        <- Result.build := @TheMaker, and it CALLS fine
handed slot   0x7ab99f600050 <- MkKind(TheMaker) from NilPy
```

So the slot does not hold a mangled address: it holds a **heap pointer**. The
carrier is stored whole, which is the "likely shape" paragraph's first branch.

**And the second branch is ruled out -- the fix is NOT "read word 0 of the
pair".** Dereferencing the carrier:

```
word 0   @TheMaker + 2149     <- a code address, and NOT TheMaker's
word 1   0
word 2   -4294967295          = 0xFFFFFFFF00000001, a refcount/tag pair shape
word 3   another .text address
word 4   40
word 5   0
```

The four unit routines sit at `@TheMaker + 0 / 102 / 200 / 325`, so word 0 is
none of them. Whatever code address the carrier holds, it is a wrapper or a
different routine entirely, and a fix that loads word 0 into the slot would
store a plausible, wrong, still-crashing address.

**Where I would go next, in order:** `PXXDBG=a.ast:` on the `MkKind(TheMaker)`
call to see what the argument node IS, then find which routine lives at
`+2149` (a map file, or an `AddrOf` arm per candidate) -- naming that routine
is what turns this from "the carrier is stored whole" into a diagnosis. Note
the pointer VALUES move per run (ASLR); the deltas do not.

Untouched by me: `PyCoerceCallableArgsIn` (compiler/pyparser.inc ~26959-27275)
and `pycallback_*` in pylib.pas. Ticket is unassigned and free.

**And frankh-c0, who holds the frontend's inference pre-pass, says the object is
the frontend doing what it thinks is right** (2026-09-20, in reply to a topic
check): *"a NilPy def's value is a class instance, not a bare pointer, wherever
the frontend has typed it ... The code address lives inside it."* So the two
halves are separable and this ticket is the second one: what lands in the slot
once the CALLEE's signature says `procedure`, not what class the frontend
inferred for the value. Do not take a heap pointer here as evidence of a
lowering bug in the inference half.

## Resolution (frankb-8e, 2026-09-20) -- commit 8826e6aec

MECHANISM. NilPy has exactly one place that coerces a callable VALUE into a raw
slot, `PyCoerceCallableArgsIn` in pyparser.inc, and it knew about `Pointer`,
`cbuf` and `cptrarray` shapes only. A procedural PARAMETER is none of those:
`ProcParamProcSig[procIdx * MAX_PROC_PARAMS + i] >= 0` marks it and nothing
read that mark, so the carrier record built by `PyMakeFuncValueFor` was stored
as-is. That record is a Python callable object, not a code address, so the
slot held a heap pointer and every call through it -- from either language --
jumped into a record header.

FIX. A new first arm in `PyCoerceCallableArgsIn`, guarded on that mark, asks
`PyCarrierNamedProc` which routine the carrier was built FOR and replaces the
argument with a plain `AN_PROCADDR` to it. `PyCarrierNamedProc` reads the
carrier's `AN_PYSIGREF` argument, whose `ASTIVal` is the original routine;
it falls back to the first `AN_PROCADDR` in the carrier, which is safe
because that fallback can only be the all-Variant `$pycallwrap_*` wrapper and
a wrapper's signature cannot pass `ProcSigCompatible`.

The signature test is the existing `ProcSigCompatible`, so a routine of the
wrong shape is not silently coerced: it gets a named warning instead
(suppressed during `PyTypingPass`, which runs the same site twice).

WHAT IS NOT FIXED, and it is the thing the ESP demo actually wants: this
delivers a PASCAL routine's address into a Pascal procedural slot. A NilPy
`def` handed to a C or Pascal callback slot still does not work, because the
code address that would have to be materialised is the carrier's, and a NilPy
def has no native-ABI entry point of that signature. Filed separately; frankH
owns the half that changes how the carrier is BUILT.

FIXTURE. `test/test_nilpy_function_into_a_procedural_parameter.npy` with
`test/nilpy_units/procslot.pas`, wired into test-nilpy, six rows all `502`:
wired-with-@ vs handed-as-a-name, crossed with called-from-Pascal and
called-from-NilPy, plus a list-element receiver so the coercion is not only
exercised through a direct local. Positive control on
stable_linux_amd64/default/pinned: segfault. The wired rows are the arm that
must NOT change and they are green under both binaries.

GATE. `make compiler/pascal26` converged; `gate.sh quick` GREEN; full
test-nilpy GREEN at compiler f99f37bcebe2.


## Log
- 2026-09-20 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit e502d115f.
