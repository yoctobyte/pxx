---
slug: umbrella-a-hosted-program-is-as-small-as-it-can-be
title: "A hosted (PC) program is as small as it can be — minimal code, constants read-only, nothing linked that is not reached"
track: A
prio: 70
type: umbrella
blocked-by: [bug-t-code-is-page-quantised-so-there-is-no-instrument-for-size-work, feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident, bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss, feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar, bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce, feature-a-unreferenced-class-rtti-keeps-every-method-alive, feature-opt-rtti-emit-on-use, feature-a-an-extern-only-variable-still-reserves-its-storage, bug-a-a-typed-const-record-is-built-by-startup-code-not-stored-as-data, bug-a-a-frontend-cannot-see-that-a-backend-calls-library-routines-it-never-mentions]
status: new
created: 2026-09-18
owner: ""
summary: "Owner-set target 2026-09-18, in two directives: \"mark as read-only where possible\" and \"strip code and associated data where possible.\" This is the PC/hosted half; the ESP half is [[umbrella-an-esp32-image-is-as-small-as-it-can-be]] and the two share most blockers. MEASURED FLOOR AT HEAD (2026-09-18, x86-64, WriteLn('hello'), verified to run): code 195 B, data 336 B, bss 41,800 B. So the code half is already excellent and the DEFAULT is not: the same program at default flags is 67,104 B of code, 4,328 B of data and the same 41,800 B of bss. Three facts frame every rung. (1) `code=` is PAGE-QUANTISED, so nothing here is gradeable until that is fixed — it is the first blocker for a reason. (2) `--dce` removes 44.7% of code and ZERO bytes of data or bss, so the size problem and the RAM problem are different problems with different passes. (3) 78% of the bss floor is one constant, SIG_ALTSTACK_SIZE = 32768, reserved even under --no-signals."
---

# The target, in the owner's words

> *"mark as read-only where possible. and strip code and associated data where
> possible."* — 2026-09-17
>
> *"so, we're up for 2 umbrella tickets. one for PC platforms - and make sure we
> can emit minimal code. and second for ESP, same goal."* — 2026-09-18

This is an **umbrella**. Do not claim it — claim a rung.

**`prio: 70` is a placeholder set by an agent.** Umbrella prio is the one number
a human sets; this one has not been set by him yet.

# What is already true, measured 2026-09-18

Every row verified to actually print `hello`. `real` is the code segment with
trailing zero padding stripped, because `code=` is the page ceiling.

| flags | `code=` | real code | data | bss |
| --- | ---: | ---: | ---: | ---: |
| `<none>` | 69,400 | 67,104 | 4,328 | 46,596 |
| `--no-signals` | 69,400 | 66,699 | 4,328 | 46,596 |
| `--dce` | 20,248 | 18,790 | 4,328 | 46,596 |
| `--dce --no-signals` | 20,248 | 18,385 | 4,328 | 46,596 |
| `-uPXX_MANAGED_STRING` | 3,864 | 600 | 336 | 41,800 |
| `-uPXX_MANAGED_STRING --no-signals` | 3,864 | **195** | **336** | **41,800** |

The 195 bytes, disassembled in full: **110 B startup prologue** (`getrlimit` on
RLIMIT_STACK, clamp to 64 MiB, `gettid`, build a four-qword thread block,
`arch_prctl(ARCH_SET_FS)` for TLS, record `rsp`) + **85 B of program**
(`write(1,"hello",5)`, `write(1,"\n",1)`, `exit_group`).

The owner's recollection was *"like 267 bytes of executable memory"* for a
Pascal hello world without ansistrings. It is 195. **That property has not
regressed; it has improved.** What regressed is the DEFAULT, and the mechanism is
known: `PasInitDefines` (`paslexer.inc:923`) defines `PXX_MANAGED_STRING`
unconditionally, so every Pascal program pulls `builtinheap` and `{$H-}` cannot
reach it. **FIXED 2026-09-22** — that define is now evidence-based; see
[[bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce]], `WriteLn('hello')`
63,760 → 4,528 B. (The routine was called `PasApplyDefaults` here and in three
code comments until the same day. No such procedure has ever existed; the name
was carried only by comments citing each other.)

# The rungs

1. **Make size measurable.** [[bug-t-code-is-page-quantised-so-there-is-no-instrument-for-size-work]].
   Nothing below can be graded without it — a 405-byte win reads as zero.
2. **Stop paying for facilities the program opted out of.**
   [[bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss]] is 78% of
   the bss floor on its own. **The readln line buffer — the other 10% — is DONE
   2026-09-18, and it was worth DOUBLE what this line said: 8,168 B, not 4,096,
   because the same buffer was reserved TWICE** in an x86-64 image, once by the
   Pascal driver (`BSS_LINE_BUF`) and once by the builtin unit (`PXXLineBuf`),
   and only the first was ever read. Empty program, x86-64: bss 46,596 ->
   38,428. i386 / arm32 / riscv32: 42,316 -> 34,140. aarch64: 42,356 -> 34,188.
   It is a pointer to a demand-allocated growable block now, so a program that
   never touches stdin reserves nothing at all.
   **NEXT IN THIS RUNG AND IT IS THE LARGEST ONE LEFT:**
   [[feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar]]
   — 3,072 B, 8% of the hosted floor, held whether or not the program declares a
   `threadvar`. **Measured x86-64-ONLY (0 on i386, aarch64 and bare ESP), so it
   is deliberately NOT wired under the ESP umbrella**, which is the opposite of
   the two items above it and is why the ticket leads with the profile table.
3. **Make the default converge on the floor.**
   [[bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce]] — the
   unconditional `PXX_MANAGED_STRING`. This is the single largest default-path
   item and it is worth ~66 KB of code and ~4 KB of data.
4. **Read-only constants.**
   [[feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident]],
   which is blocked in turn by the two tickets that make constants actually
   constant. This is the owner's first directive and on hosted targets it buys
   page permissions and sharing rather than bytes — **the bytes are on the ESP
   side**, which is why the two umbrellas are separate.
5. **Strip data, not just code.**
   [[feature-a-unreferenced-class-rtti-keeps-every-method-alive]],
   [[feature-opt-rtti-emit-on-use]],
   [[feature-a-an-extern-only-variable-still-reserves-its-storage]]. `--dce`
   drops procedure bodies and provably removes zero bytes of data or bss;
   everything in this rung is the other half.
6. **Close the frontend/backend visibility hole.**
   [[bug-a-a-frontend-cannot-see-that-a-backend-calls-library-routines-it-never-mentions]].
   A pass that cannot see what the backend emits cannot strip it, and the signal
   runtime is the worked example: it is backend-emitted machine code, not Pascal
   procedures, so `procs=0` and DCE is structurally blind to it.

# The trap this umbrella exists to prevent

**`code=` and SRAM are different quantities and the seat that opened this
confused them.** On a hosted target code is demand-paged from the file and never
all resident; on ESP the bare profile loads code into IRAM. A ticket that reports
a code-size win as a memory win is wrong on both targets for different reasons.
Say which segment, and say which profile.
