---
prio: 55
---

# Metaclass construction WITH ARGUMENTS segfaults on every non-x86-64 target

- **Type:** bug (cross-target codegen)
- **Track:** A — core (AN_METACLASS_NEW lowering / per-backend arg marshalling)
- **Status:** backlog — opened 2026-07-13.
- **Found by:** the typed-metaclass work for fpcunit ([[feature-pascal-corpus-fpcunit]]).
  PRE-EXISTING — reproduces with the old `Create` spelling and the old code path; the
  typed-metaclass change neither caused nor touches it.

## Symptom
Constructing through a class reference works only when the constructor takes NO arguments:

```pascal
type
  TB  = class F: string; constructor Create(const n: string); virtual; end;
  TBC = class of TB;
  TD  = class(TB) constructor Create(const n: string); override; end;
var tc: TBC; o: TB;
begin
  tc := TD;
  o := tc.Create('x');      { SEGFAULT on i386 / aarch64 / arm32 / riscv32 }
  writeln(o.F);             { correct on x86-64: 'd:x' }
end.
```

Measured 2026-07-13:

| target | `tc.Create` (no args) | `tc.Create(arg)` |
| --- | --- | --- |
| x86-64 | ok | ok |
| i386 | ok | **segfault** |
| aarch64 | ok | **segfault** |
| arm32 | ok | **segfault** |
| riscv32 | **segfault** | **segfault** |

So the *dispatch* (allocate the dynamic class, call its virtual constructor) is right
everywhere except riscv32; it is the ARGUMENT MARSHALLING through AN_METACLASS_NEW that
is x86-64-only. riscv32 fails a step earlier and needs its own look.

## Why it matters
This is the shape a class FACTORY takes — `GetClass(name)` → construct → configure — so it
is on the path for streaming/.lfm and for any registry-driven construction. fpcunit's suite
builder hits it directly (`tc.CreateWith(ml[i], SN)`), which is how it surfaced; the
fpcunit chain is green on x86-64 and would fault the moment it ran cross.

`test/test_typed_metaclass_b278.pas` covers the x86-64 behaviour and is deliberately NOT in
any cross list until this is fixed — see the note in that file.

## Where to look
`AN_METACLASS_NEW` in `ir.inc` (BuildMetaclassNew builds it) and its per-backend emit. The
no-arg case working everywhere but x86-64 says the args are being placed by an x86-64-shaped
assumption (register order / the hidden Self slot ordering relative to the allocated
instance), so compare against how AN_CALL marshals a normal constructor's args on each
backend — that path is known good.

## Gate
`make test` + self-host byte-identical + cross (this IS the cross gate).
