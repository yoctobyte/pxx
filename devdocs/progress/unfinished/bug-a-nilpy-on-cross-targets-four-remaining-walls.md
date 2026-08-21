---
track: A
prio: 40
type: bug
blocked-by: []
summary: "After the string-tagged-binop gate was lifted, NilPy still does not RUN on any cross target: arm32 builds and SIGILLs, i386 refuses on `symbol kind not supported yet (load)`, aarch64 on `aggregate result with more than 8 params`, riscv32 on bare-metal mmap. Four separate walls, one campaign — ~53 .npy tests are cross-blind until they fall."
status: unfinished
owner: claude-A
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

## Progress — arm32 is GREEN (2026-08-21)

Three defects, all the same disease, all fixed together:

1. **`EmitProgramEntryForTarget`** (new, `ir_codegen.inc`, next to
   `EmitIoLockStubsForTarget`) — the entry stub's six per-arch arms, lifted out
   of the Pascal driver verbatim, plus an optional mmap heap arena for the NilPy
   allocator model. The Pascal driver passes `False`, NilPy `True`.
2. **`PatchProgramEntryJump`** (new, same place) — the *other* half. Missed on
   the first pass: the NilPy driver kept its own
   `Patch32(jmpPatch, CodeLen - (jmpPatch + 4))`, which wrote a raw byte offset
   over an ARM branch word. The stub was correct and the program SIGILLed four
   instructions later. The two halves are one thing and now live together.
3. **`EmitMmapArena(len)`** (`emit.inc`) — real i386 / arm32 / aarch64 syscall
   arms (mmap2(192) / mmap2(192) / mmap(222)). It used to Error for xtensa and
   riscv32 and silently emit x86-64 for the other three. Length is a parameter
   now, because every ABI wants it in a different register and hiding that in
   the caller is what made the lie possible.
4. **`EmitAnsiStringRuntime` is x86-64 machine code** and the NilPy driver
   called it unguarded — the Pascal and C drivers both have
   `and (TargetArch = TARGET_X86_64)`. The blob was never executed; its length
   is not a multiple of 4, so it shifted every ARM instruction after it two
   bytes out of alignment and the first real proc decoded as garbage. That was
   the second SIGILL.

### Measured

- `def main(): print(1+2)` on arm32: **runs, prints 3**. First NilPy program
  ever to execute on a cross target.
- 60-test `.npy` differential vs the native oracle on arm32:
  **8 match, 34 BUILDFAIL, 10 run-but-wrong** (8 of the 60 fail natively too and
  are excluded). Was 0 match / 52 BUILDFAIL.
- **All 34 remaining BUILDFAILs are one wall**:
  `target arm32: IR op not yet supported: zero_sym`. Filed separately.
- The Pascal driver's arm32 output is **byte-identical** across the extraction
  (`cmp` on a hello-world arm32 binary built before and after) — the lift is a
  pure refactor on that side.
- Self-host fixedpoint + `tools/gate.sh quick` GREEN.

### Still open

| target | wall |
| --- | --- |
| arm32 | `IR op not yet supported: zero_sym` (34 of 52) — the one thing between here and broad NilPy-on-arm32 |
| i386 | `symbol kind not supported yet (load)` |
| aarch64 | `aggregate result with more than 8 params not supported` |
| riscv32 | bare-metal profile has no mmap |

The other eight frontend drivers (`fparser`, `bparser`, `aparser`, `gparser`,
`lparser`, `wparser`, `eparser`, `rparser`, `zparser`) still open-code an
x86-64 entry stub. They were NOT converted here: each has a different shape
(some emit no jump at all, some `call main` with their own exit tail), they are
all x86-64-only frontends today, and a blind sweep would be churn without a
gate to catch it. The C driver has its own per-target case already. When one of
those frontends grows a cross target, `EmitProgramEntryForTarget` is what it
should call.

## Progress — `zero_sym`, and the wall behind it (2026-08-21)

`IR_ZERO_SYM` existed on x86-64 and i386 only; arm32, aarch64 and riscv32 all
raised `IR op not yet supported: zero_sym`. Added to all three (pointer-width
store for a scalar / dyn-array handle, `PXXMemZero` for a managed span), cloned
from the two arms that had it.

- 60-test `.npy` differential on arm32: **broke=0**, every one of the 34
  BUILDFAILs now BUILDS. Match went 8 -> 9.
- 53-test dyn-array + interface differential over all four cross targets:
  **broke=0 fixed=0** — the new arms never fire for Pascal, which zero-inits
  through the parser's prologue pass instead.
- Self-host fixedpoint + `tools/gate.sh quick` GREEN.

### The wall behind it: NilPy's PROC PROLOGUE is raw x86-64

Of the 52 runnable `.npy` tests on arm32: **9 match, 1 BUILDFAIL, 42 wrong — and
38 of those 42 are `rc=-4` (SIGILL) with no output at all.** Same signature as
before: `qemu-arm -d in_asm` shows the instruction stream two bytes out of
alignment, i.e. an odd-length x86-64 blob spliced into the ARM code.

The source this time is the NilPy function prologue. `PyEmitParamSpills`
(`pyparser.inc:17433`) and `PyInitVariantLocals` (`pyparser.inc:1924`) emit raw
x86-64 — `mov rax, rdi` (3 bytes, hence the 2-byte drift), `mov [rbp+off], rax`,
`mov qword [rbp+off], 0` — and are called unguarded from **three** proc-emission
sites (`pyparser.inc:28113`, `28561`, `31624`). `v1.npy` survives only because
`main()` takes no parameters.

This is NOT a small guard like the last three. The Pascal driver does not have a
shared param-spill to call: `pasparser_proc.inc:1842` onward is several hundred
lines of per-target spill logic living *inside the driver*, which is exactly
what **`refactor-a-the-missing-layer-between-frontends-and-backends`** (prio 50,
Track A) exists to fix. NilPy-on-cross needs that layer; bolting a fourth
per-target copy into `pyparser.inc` would be the wrong fix and would make the
refactor harder.

**Parked here.** The campaign's next step is the refactor ticket, not another
patch in this one.
