---
slug: bug-a-the-arm32-hosted-compiler-wants-4x-the-arenas-and-dies-unchecked-at-enomem
track: A
prio: 50
type: bug
status: backlog
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "The arm32-hosted compiler building compiler.pas maps FIFTEEN 256 MiB arenas and the fifteenth returns ENOMEM; the native x86-64 compiler does the same build in FOUR. A 32-bit target has half the pointer width and should want LESS address space, not 3.75x more. Two separable defects: (1) the appetite, unexplained and the real blocker for arm32 self-hosting; (2) PXXAlloc does not check the mmap return -- deliberately, per builtinheap.pas:977 -- so the -ENOMEM becomes the heap base and the next write faults, which is why an out-of-memory condition arrives as an anonymous SIGSEGV instead of a diagnostic. Split out of bug-a-no-cross-target-can-build-the-compiler-itself, whose write-after-free was a DIFFERENT and now-fixed defect; do not read this as that fix not working. A mid-size input uses ONE arena on both targets, so the divergence is scale-dependent and does not reproduce small."
---

# The arm32-hosted compiler wants 4x the arenas, then dies unchecked at ENOMEM

## Measured

`qemu-arm -strace`, arm32-hosted build of `compiler/compiler.pas`:

```
mmap2(NULL,268435456,...) = 0x40802000     <- 14 of these succeed
...
mmap2(NULL,268435456,...) = -1 errno=12 (Cannot allocate memory)
```

**15 calls, every one for the 256 MiB `HEAP_ARENA`, the 15th refused.** 3.5 GB
mapped in a 32-bit address space.

`strace`, the same source built by the native x86-64 compiler: **4 arenas**, and
`/usr/bin/time` puts peak RSS at **549 MB**. Mapping is roughly 2x RSS there.

| | arenas for `compiler.pas` | address space |
| --- | --- | --- |
| native x86-64 | 4 | 1 GB |
| arm32 (hosted, qemu-user) | 15 (14 granted) | 3.5 GB, then ENOMEM |
| either, on a mid-size `uses sysutils, math` program | 1 | — |

The last row matters: **it does not reproduce on a small input**, so a reduction
will not find it.

## The crash, and why it has no error message

Guest core (`qemu-arm` writes one under `ulimit -c`; the system gdb has no arm
target):

```
pc = PXXAlloc+0xc2c    instruction: STR r1, [r0]
r0 = 0xfffffff4 = -12          r7 = 0xc0 = 192 = mmap2
```

`r0` is loaded from a local and written through immediately. `builtinheap.pas:977`
documents this as intended: *"PXXAlloc, which does NOT check the result
(deliberately -- on a hosted target a failed mmap returns a negative errno and
the next access faults), so the returned value IS the base of the heap."*

## Two defects, and they are worth separating

1. **The appetite.** Unexplained, and it is the actual blocker for arm32
   self-hosting. 32-bit pointers are half the size; the header is a fixed 24
   bytes on every target, so headers cannot account for 3.75x. Leak, poor reuse
   across arenas, or per-allocation waste — not yet distinguished. The next
   measurement is `-dPXX_ALLOC_CENSUS` on both targets: **same bytes allocated
   means a reuse/fragmentation bug; more bytes means a sizing bug.**
2. **The unchecked return.** Cheap to fix and independent of (1): one compare
   turns an anonymous SIGSEGV into "out of memory". The existing comment's
   rationale is about targets with no page protection (wasm32 shipped a heap at
   address zero), which does not apply to a hosted target that has a real errno
   to report. Note this is a stated design decision, so changing it is a
   deliberate reversal, not a bug fix — say so in the commit.

## Not to be confused with

[[bug-a-no-cross-target-can-build-the-compiler-itself]]. That ticket's
write-after-free was a one-byte store into a pointer slot on
arm32/riscv32/xtensa, fixed in `5454ef402` and confirmed independently by frankS
against the original symptom on both of its axes. This is what is left after it,
and the heap debugger is silent on it — zero reports of every family, on an
instrument that fires on plant controls for all three.

## Gate

`make compiler/pascal26` plus the two `-strace` counts above.
