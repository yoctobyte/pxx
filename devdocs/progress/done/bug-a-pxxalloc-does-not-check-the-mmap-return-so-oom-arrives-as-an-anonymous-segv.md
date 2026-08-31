---
slug: bug-a-pxxalloc-does-not-check-the-mmap-return-so-oom-arrives-as-an-anonymous-segv
track: A
prio: 45
type: bug
status: done
found: 2026-08-31
found-by: frankA
owner: frankB
blocked-by: []
summary: "FIXED 2026-09-01. PXXAlloc now checks HeapMmap's return and reports instead of faulting: measured contrast on the same program under the same 200 MB cap, pinned 992065f21f33 gives Segmentation fault / exit 139 / no output, f23f141f997d gives 'pxx: out of memory (heap arena mmap failed)' / exit 203. A DELIBERATE REVERSAL of the decision stated at HeapMmap's terminal arm, and narrower than it: that rationale is about targets with no page protection, not a hosted one with a real errno. The subtlety is that the test is the ERRNO RANGE, never the sign -- i386 zero-extends a high address and sign-extends only [-4095,-1], while arm32 sign-extends unconditionally, so p < 0 would report OOM for a good mapping on the very target this was measured on. The APPETITE half was already split out to bug-o-the-in-place-string-append-is-x86-64-only."

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


## 2026-08-31 — the appetite half is explained; this ticket narrowed to the unchecked return

Renamed from `bug-a-the-arm32-hosted-compiler-wants-4x-the-arenas-and-dies-unchecked-at-enomem`, because both halves of that name became wrong: it is not
arm32 (i386 shows the identical 15-arena failure natively, frankS, 094e41720),
and the appetite is no longer unexplained.

`s := s + x` is O(n) on x86-64 and O(n^2) on every other backend — 20000 one-char
appends cost 10 allocations on x86-64 and 19780 on i386, arm32, aarch64 and
riscv32 alike. The recogniser and emitter are hand-written x86-64 machine code in
`ir_codegen.inc`; the runtime half `PXXStrAppend`, with the doubling that makes
it O(n), is shared and simply never called by anything else. Full measurements:
`bug-o-the-in-place-string-append-is-x86-64-only-so-every-other-backend-is-quadratic`.

**Stated at the strength it was measured, which is not "proven":** the mechanism
is proven in isolation (ten-line repro, five targets) and the compiler's own
allocation profile has its shape — 5931 of the first 19780 allocations above the
top census bin carrying 4.4 GB, creeping +8/+24/+40 and never doubling, against
the same buffers going 41943064 -> 83886104 on an x86-64 host. What has NOT been
done is attributing those 5931 allocations to the append path by instrumenting
their call site. **Who owns "then what?": whoever lands the append fix re-runs
the 32-bit self-build and reports the arena count.** If it does not drop to ~4,
there is a second consumer here and this ticket widens again.

Host and target were separated by control: an x86-64 host building for
`--target=i386` and `--target=arm32` completes normally (20.6M allocs, 1.72 GB,
4 arenas), so the target is not the variable — the backend that compiled the
*running* compiler is.


---

## 2026-09-01 — fixed

`HeapPtr := HeapMmap(arena)` is now followed by
`if HeapMmapFailed(HeapPtr) then PXXHeapExhausted;`. Three things were less
obvious than "one compare".

**1. The test is the errno RANGE, not the sign.** The kernel reserves
[-4095,-1] for `-errno`, but the 32-bit backends widen a syscall return to
Int64 by two different conventions:

| backend | errno range | a high address (bit31 set) |
| --- | --- | --- |
| i386 (`ir_codegen386.inc`) | sign-extends NEGATIVE | zero-extends POSITIVE |
| arm32 (`ir_codegen_arm32.inc`, `mov r1, r0, asr #31`) | sign-extends NEGATIVE | **sign-extends NEGATIVE** |

So `p < 0` — the obvious form, and the one arm32's own comment implies is
correct — would report out-of-memory for a perfectly good mapping at or above
`$80000000`, which is ordinary in the 3.5 GB space this ticket measured. The
range test is right under both conventions, because a sign-extended high address
lands far BELOW -4095. **Do not "simplify" it to a sign test.**

`p = 0` is the other failure and is not hosted-specific: the wasm/bare arena is
handed out once and `HeapMmap` returns 0 after, and 0 is the value the terminal
arm's own comment names as the one that fails silently where there is no page
protection.

**2. The reporter must not allocate.** It runs when the allocator has just
failed, so `writeln` — which builds a string — would re-enter `PXXAlloc`. It
writes a byte at a time through `PXXSysWrite`, exactly as `PXXDbgFlush`'s
reporter does and for the same reason. `Halt(203)` is FPC's heap-overflow
runtime error, so a caller reading `ExitCode` sees FPC's number rather than a
pxx invention.

**3. It is a REVERSAL, not a bug fix, and the original decision keeps its
scope.** `HeapMmap`'s terminal-arm comment justifies not checking with "on a
hosted target a failed mmap returns a negative errno and the next access
faults". That reasoning is about targets with NO page protection, where 0 is the
value that fails silently — the wasm32-heap-at-address-zero case. It does not
apply to a hosted target that has a real errno to report. The `Result := -1`
arm is unchanged; it now reaches a message instead of a fault.

### Measured

Same source, same 200 MB `ulimit -v` — below the 256 MB `HEAP_ARENA`, so the
FIRST request is refused and the failure is deterministic rather than dependent
on what the box happens to have free:

| compiler | result |
| --- | --- |
| pinned `992065f21f33` | `Segmentation fault (core dumped)`, exit **139**, no output |
| `f23f141f997d` | `pxx: out of memory (heap arena mmap failed)`, exit **203** |

Unconstrained, the same program still allocates a gigabyte and exits 0, so the
check costs nothing on the success path.

### Regression test

`test/test_heap_oom_reports.pas`, wired in the Makefile beside the other
`ulimit` tests. It asserts the exit code AND the message: either alone would
pass for the wrong reason — a segfault a shell happened to report as 203, or a
message printed on a path that then carried on. Its positive control is its own
history rather than an assertion: the pinned compiler demonstrably fails it,
measured above.

`gate.sh quick` GREEN.

### Who owns "then what?"

Nothing here, and that is deliberate. The arena APPETITE — why a 32-bit
self-build wanted 15 arenas — is
[[bug-o-the-in-place-string-append-is-x86-64-only-so-every-other-backend-is-quadratic]],
which already carries the open obligation: whoever lands the append fix re-runs
the 32-bit self-build and reports the arena count. This ticket never claimed
that half. What changes is that if the count does NOT drop, the next person sees
a message instead of a core file.

## Log
- 2026-09-01 — resolved, commit 4419e1aa7.
