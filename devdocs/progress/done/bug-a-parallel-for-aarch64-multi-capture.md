---
prio: 40
track: A
---

# aarch64: `parallel for` with 2+ captures → Bus error (alignment)

- **Type:** bug — cross-codegen (aarch64), Bus error (SIGBUS/misalignment).
- **Found:** 2026-07-17, qemu run-verification of parallel-for cross targets.
- Track A (aarch64 backend / codegen). Feature is target-agnostic IR; only
  aarch64 mislowers it.

## Symptom (precise parity boundary)

`parallel for` capturing enclosing locals, under `qemu-aarch64`:
- **1 capture** (any type/size, incl. a 1000-int fixed array): OK
- **2 captures**: Bus error (signal 7)
- **3 captures**: OK

i386 and arm32 run ALL of these correctly. x86-64 fine. So it is aarch64-only and
tracks the capture COUNT, not size/type.

Minimal repro (bus-errors on aarch64, OK on i386/arm32/x86-64):
```pascal
program twofix; uses palparallel;
type TG = array[0..9] of Integer;
var r: array[0..9] of Integer;
procedure Q; var g, h: TG; i: Integer;
begin
  for i:=0 to 9 do begin g[i]:=0; h[i]:=0; end;
  parallel for i:=0 to 9 do begin g[i]:=i; h[i]:=i*10; end;   { 2 captures: g, h }
  for i:=0 to 9 do r[i]:=g[i]+h[i];
end;
begin Q; writeln(r[3]); end.
```
Build: `pascal26 --threadsafe --target=aarch64 twofix.pas out; run_target.sh aarch64 out`.

## Likely root cause

The worker's OWN frame is 16-aligned (`sub sp,sp,#0x30` for 2 caps). The
misalignment is in the capture ACCESS / the `Pointer(NativeInt(ctx)+off)`
preamble, which on aarch64 uses stack push/pop (`str x0,[sp,#-16]!` / `ldr
x0,[sp],#16`) for the binop — an odd count may leave SP or a load misaligned at a
16-byte-aligned access. The exact faulting PC still needs pinning (qemu -d didn't
surface it cleanly).

Possibly the SAME aarch64 root cause as: with per-arch affinity enabled
(feature per-arch sched_getaffinity), aarch64 `QueryCpuCount` (a 128-byte Int64
array + popcount) also bus-errored, though the same code runs fine in isolation —
smells like an aarch64 stack-layout/alignment codegen bug surfacing under certain
frame shapes.

## Direction

Get the fault PC (qemu-aarch64 core / gdb), inspect the faulting ldr/str's
address alignment, and fix the aarch64 codegen (frame/SP alignment or the
push/pop binop path). Gate = the repro runs on aarch64 + self-host + cross. Add
the 2-capture repro as a regression once green.

## Unblocks

Full `parallel for` capture on aarch64 (single-capture + capture-free already
work). i386/arm32 already pass all capture tests.

## Log
- 2026-07-17 — resolved, commit b79c2cdc.
