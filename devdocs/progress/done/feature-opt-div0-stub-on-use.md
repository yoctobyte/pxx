---
prio: 25
---

# x86-64 div-by-zero abort stub is emitted unconditionally, even for division-free programs

- **Track:** A (codegen). **Tag:** O (size). x86-64 only.
- **Found:** 2026-07-16, alongside [[feature-opt-rtti-emit-on-use]] while dissecting
  the frozen `hello` demo's size.

## Symptom

`EmitDiv0Stub` (parser.inc ~24210) runs for every x86-64 build:

```pascal
if TargetArch = TARGET_X86_64 then EmitDiv0Stub;
```

It emits the shared div-by-zero abort stub **plus** the 37-byte string
`"Runtime error 200 (division by zero)"` into `.data` — even when the program
contains no `div`/`mod`/`/`-on-integer site that could ever branch to it. ~40 B of
dead code+data in a division-free binary. Only visible as noise on a tiny frozen
build, but it is pure waste there.

## Fix

Gate the stub on "an integer div/mod site was actually emitted" — set a flag when a
div/mod IR op is lowered on x86-64, and emit the stub (and intern its string) only
if that flag is set. Division-free programs then carry neither the stub nor the
string. The div/mod codegen already references `Div0StubAddr`; that reference is
what the flag tracks.

## Notes

- Correctness is unaffected: a program with no division never branches to the stub,
  so removing it when unused changes nothing observable.
- Low priority — it is a small, x86-64-only size trim. The bigger baseline item is
  the RTTI one ([[feature-opt-rtti-emit-on-use]]), which also hits ESP.
- Gate = self-host byte-identical (the self-host compiler HAS division, so its own
  build is unchanged) + a division-free program shrinks + quick.

## Log

- 2026-07-18 (fable-O) LANDED, with a twist. Prescan (`DetectPascalRuntimeNeeds`
  gains `needsDivStub`: tkDiv/tkMod tokens) gates the stub — but the TICKET
  PREMISE was incomplete: the stub is NOT dead in division-free programs when
  builtinheap is pulled, because builtinheap's OWN early div sites (compiled
  before PXXDivZero registers; FindProc misses mid-unit) fall back to the stub.
  And the default-RTL `uses` injection precedes the scan, so needsHeap (kept in
  the condition) retains the stub for every default build → Pascal output
  byte-identical to pinned across the board. The trim only fires for genuinely
  heap-free division-free sources.
  **The real find:** the C and NilPy drivers NEVER emitted the stub — their
  builtinheap early div sites emitted `call 0` (into the entry stub) on the
  div-by-zero path. Latent silent-corruption bug, exposed by the new safety net
  (`Div0StubAddr = 0` at a stub-needing site → hard compiler error) and fixed:
  both drivers now emit the stub unconditionally, BEFORE their RTL pulls.
  Gates: self-host byte-identical, test-opt green, C 220/220, test-nilpy,
  hasdiv/nodiv byte-identical to pinned, C div-by-zero exits RE200.
- 2026-07-18 — resolved, commit 938c0154.
