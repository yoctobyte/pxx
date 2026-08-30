---
slug: bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows
track: A
prio: 55
type: bug
blocked-by: []
status: backlog
found: 2026-08-30
summary: "The rel8 patch idiom `Code[p] := Byte(CodeLen - (p + 1))` truncates without any diagnostic when the span exceeds 127 bytes. A forward jump silently becomes a BACKWARD jump into the middle of an instruction. Measured: a jns meant to skip 181 bytes was written as -75 and the program segfaulted at a mid-instruction address. Latent today; armed the moment any emitter between a patch site and its target grows."
---

# A rel8 jump patch truncates silently when its span grows

The idiom, used at ~30 sites across `symtab.inc`, `ir_codegen.inc`,
`exception_emit.inc` and `emit.inc`:

```pascal
EmitB($79); jnsOff := CodeLen; EmitB(0);    { jns .pos — placeholder }
...
Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
```

`Byte()` truncates. There is no range check and no diagnostic. When the emitted
span between the placeholder and its target exceeds **127 bytes**, the forward
displacement wraps into a negative `rel8` and the jump goes **backwards**,
usually into the middle of an instruction.

## Measured, not reasoned

Found while growing `EmitSyscall` from 2 bytes to ~140 for
[[feature-port-rtl-over-libc]] (that work is reverted; this defect is not).

- The program faulted with `rip = 0x411115`, which is **mid-instruction** — the
  `add $0x80,%rsp` at `0x41110f` is 7 bytes and spans through `0x411115`. A
  mid-instruction `rip` can only be reached by a jump.
- Scanning the executable segment for any `rel8` jump targeting that address
  found exactly one: **`0x41115e: jns rel8, displacement -75`**.
- The intended forward distance at that site (`symtab.inc:9789`) was **181**
  bytes. `181` written as a byte and read back as a signed `int8` is **-75**.

`181 - 256 = -75` is an exact match, so the mechanism is arithmetic, not
inference.

## Why it is worth fixing rather than noting

**It is silent in both directions.** The compiler emits no diagnostic, and the
resulting binary crashes far from the emitter that grew — the fault address is
inside an unrelated instruction, and the emitter that caused it is not on the
stack. This is the repo's expensive shape: a plausible wrong result far from
the cause.

**Today it is latent, not live.** No current emitter spans 127 bytes at these
sites, so every existing patch is in range and the default build is correct.
That is exactly what makes it a landmine: it is armed by *growing an emitter*,
which is a normal thing to do, and it gives no signal that a limit was crossed.
`--rtl-libc` is the first thing to trip it, and only in a non-default mode.

## Fix

Replace the raw `Byte(...)` stores with a checked helper, e.g.:

```pascal
procedure PatchRel8(patchPos: Integer);
var d: Integer;
begin
  d := CodeLen - (patchPos + 1);
  if (d < -128) or (d > 127) then
    Error('rel8 jump span ' + IntToStr(d) + ' exceeds the one-byte '
          + 'displacement: widen this jump to rel32');
  Code[patchPos] := Byte(d);
end;
```

An `Error` is the right response rather than auto-widening: widening changes
every downstream offset and the sites differ in whether they can absorb that,
so the emitter's author should choose. The point is that the limit becomes
**loud at compile time** instead of silent at runtime.

Sites to convert: every `Code[<x>] := Byte(CodeLen - (<x> + 1));` and the
inline `EmitB(Byte(<target> - (CodeLen + 1)));` back-edge form.

## Gate

`make compiler/pascal26` (self-host fixedpoint) — the conversion must be a pure
refactor with the default build byte-identical, which is checkable by comparing
emitted programs against the pinned binary, not only by the fixedpoint (see
face 190: the fixedpoint proves self-consistency, not unchanged output).
