---
track: N
prio: 55
type: bug
owner: unassigned
blocked-by: []
summary: "`MkKind(TheMaker)` — a Pascal function name passed from NilPy into a Pascal `function(...)` procedural PARAMETER — stores something that is not a code address, and every later call through it segfaults, INCLUDING a call made from Pascal. Wiring the identical field inside Pascal with `@TheMaker` gives 502 through both languages. The call site is innocent; the value is wrong. Present in the pin."
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
