---
track: A
prio: 40
type: bug
blocked-by: []
summary: "After the string-tagged-binop gate was lifted, NilPy still does not RUN on any cross target: arm32 builds and SIGILLs, i386 refuses on `symbol kind not supported yet (load)`, aarch64 on `aggregate result with more than 8 params`, riscv32 on bare-metal mmap. Four separate walls, one campaign — ~53 .npy tests are cross-blind until they fall."
status: backlog
owner: ""
---

# NilPy on cross targets: four remaining walls

- **Track A** (the i386 / arm32 / aarch64 / riscv32 backends). NOT Track N —
  the NilPy frontend is fine; these are backend gaps that happen to be reachable
  only through the NilPy runtime's Pascal source (`compiler/builtin/pyeval.pas`
  and friends).
- Opened 2026-08-21, immediately after
  `bug-a-a-string-tagged-address-binop-walls-off-nilpy-on-three-targets` moved
  the wall from "refuses" to these four.

## The probe

```sh
cat > /tmp/v1.npy <<'PY'
def main():
    a = 1
    b = 2
    print(a + b)
main()
PY
for t in i386 arm32 aarch64 riscv32; do
  ./compiler/pascal26 --target=$t /tmp/v1.npy /tmp/v1_$t && tools/run_target.sh $t /tmp/v1_$t
done
```

## Current walls (2026-08-21, at the sha that resolved the binop gate)

| target | wall |
| --- | --- |
| **arm32** | **builds**, then `qemu: uncaught target signal 4 (Illegal instruction)` — **diagnosed, see below**. |
| **i386** | `target i386: symbol kind not supported yet (load)` |
| **aarch64** | `target aarch64: aggregate result with more than 8 params not supported` |
| **riscv32** | `mmap not supported on bare-metal target` — riscv32 is a bare-metal profile, so the NilPy runtime's heap needs the same treatment the ESP profile got. Possibly the odd one out and not worth chasing with the other three. |

## The arm32 SIGILL is not an arm32 bug — the NilPy driver emits an x86-64 entry stub

Measured 2026-08-21. The ELF header says ARM; the bytes at the entry point are
**x86-64**:

```
h_arm32  (Pascal hello)  @0x74: 00109fe5 000000ea ... ldr r1,[pc] / b .+8   <- ARM
v1_arm32 (NilPy hello)   @0x74: 48892425 60502b08 48be...              <- mov %rsp,0x82b5060
                                                                          movabs $0x10000000,%rsi
```

`compiler/pyparser.inc:~34622` writes the NilPy program prologue as raw x86-64
bytes with **no target dispatch at all**:

```pascal
EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
MovRsiImm(HEAP_ARENA_SIZE);
EmitMmapArena;
EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
...
EmitB($E9); jmpPatch := CodeLen; EmitI32(0);          { jmp main }
```

The Pascal driver has the per-target version of exactly this
(`pasparser_prog.inc:929-1045` — i386 / arm32 / aarch64 / xtensa / riscv32 /
x86-64 arms, each saving the initial sp and branching to the main body). The
NilPy driver never got it. Neither did the other frontends: `fparser.inc:357`,
`bparser.inc:689`, `aparser.inc:361`, `gparser.inc:373`, `lparser.inc:305`,
`wparser.inc:220`, `eparser.inc:533` all emit the same `48 89 24 25` blind.

`EmitMmapArena` (`emit.inc:163`) is the same shape one level down: it *Errors*
for xtensa and riscv32 and then **silently emits x86-64** for i386, arm32 and
aarch64. A refusal for two targets and a lie for three.

So the fix is not an arm32 codegen feature. It is the shared-entry-stub
extraction the Pascal driver's arms are already the reference for:

1. lift `pasparser_prog.inc`'s per-target entry stub into one
   `EmitEntryStubForTarget(var jmpPatch)` next to `EmitIoLockStubsForTarget`
   (which exists for precisely this reason — read the comment at
   `pasparser_prog.inc:1080`: *"The per-arch choice used to be spelled out here,
   in the Pascal driver only, which is precisely why the other eight frontends
   shipped without it."*);
2. give `EmitMmapArena` real arms (or an `Error`) for i386/arm32/aarch64 so it
   can never lie again;
3. call both from the NilPy driver, then from the other seven.

That is one change that unblocks arm32 and moves i386/aarch64 to their next
wall, instead of three per-target patches. Rank it as the first step here.

Take the rest one at a time; each is an ordinary backend gap with the two-line
probe above and the playbook in `devdocs/dev/debugging-playbook.md`.

## Why it matters

~53 `.npy` tests exist and none of them has ever run on a cross target. They
show up in any cross differential as BUILDFAILs and get misread as record or
variant gaps — that is exactly how this was found. Every one of the four walls
is worth a separate ticket once someone starts; this one is the index.

## Gate

Per wall: the probe builds and runs on that target; self-host fixedpoint +
`tools/gate.sh quick`.
